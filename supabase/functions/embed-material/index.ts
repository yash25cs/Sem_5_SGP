import { encodeBase64 } from 'jsr:@std/encoding@1/base64';

import {
  documentText,
  embedTexts,
  interact,
  parseJsonObject,
} from '../_shared/gemini.ts';
import { HttpError, json, readJson, requireUser, serve } from '../_shared/supa.ts';

/// Turns an uploaded study material into retrievable chunks.
///
/// Body: `{ materialId: string, force?: boolean }`. The caller is taken from the
/// JWT, never from the body — see `requireUser`.
///
/// The order of the last two steps is load-bearing:
/// `app_private.material_status_guard()` (0009_atomicity.sql) raises 23514 if
/// `status` becomes `embedded` while the material has no chunks, and it fires for
/// every role including `service_role`. So chunks are written first, then the
/// status flips.

/// Roughly the largest PDF worth inlining. Base64 inflates by 4/3, and the
/// Interactions request has to stay under the 20 MB inline cap — the Files API
/// is the answer above this, and that's a follow-up, not a silent truncation.
const MAX_PDF_BYTES = 14 * 1024 * 1024;

/// Plain text is cheap to hold in memory but a 5 MB syllabus dump would be
/// hundreds of chunks and hundreds of embedding calls.
const MAX_TEXT_BYTES = 2 * 1024 * 1024;

/// Upper bound on chunks per material, so one enormous document can't spend the
/// whole day's Gemini quota. Anything past this is dropped and logged.
const MAX_CHUNKS = 120;

/// Target size of a locally split text chunk, and how much of the previous one
/// each chunk repeats so a definition split across a boundary still retrieves.
const TEXT_CHUNK_CHARS = 1200;
const TEXT_OVERLAP_CHARS = 150;

/// Longest chunk we'll store. Retrieval feeds six of these into one prompt.
const MAX_CHUNK_CHARS = 4000;

interface Section {
  unitLabel: string | null;
  text: string;
}

const PDF_SCHEMA = {
  type: 'object',
  properties: {
    sections: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          unit_label: { type: 'string' },
          text: { type: 'string' },
        },
        required: ['text'],
      },
    },
  },
  required: ['sections'],
};

const PDF_INSTRUCTION = `You transcribe a student's study material into ordered, \
retrievable sections.

Rules:
- Work through the document front to back. Do not summarise, reorder, or add \
anything that isn't in it.
- Each section is roughly 150 to 300 words of the document's own text. Break at \
natural boundaries — a heading, a topic change, the end of a list.
- unit_label is the nearest enclosing unit, chapter, module or topic heading, \
copied as printed (for example "Unit 3 — Normalisation"). Leave it out when the \
page has no heading above the text.
- Skip page furniture: page numbers, running headers and footers, the index.
- Keep tables and lists as readable plain text.
- A photo of handwritten or printed notes is read the same way: transcribe the \
handwriting faithfully, including formulas, and skip anything illegible rather \
than guessing at it.
- Return every section of the document, in order. If the document runs longer \
than 120 sections, start from the beginning and stop at 120.`;

serve(async (req) => {
  const { supa, userId } = await requireUser(req);
  const body = await readJson(req);

  const materialId = typeof body.materialId === 'string'
    ? body.materialId.trim()
    : '';
  if (materialId.length === 0) {
    throw new HttpError(400, 'That request was malformed.');
  }
  const force = body.force === true;

  // Read through the caller's client: RLS makes "someone else's material" look
  // exactly like "no such material", and both are honestly a 404 from here.
  const { data: material, error: readError } = await supa
    .from('materials')
    .select('id, source_type, storage_path, title, status, subject_id')
    .eq('id', materialId)
    .maybeSingle();

  if (readError) {
    console.error('Could not read material', readError);
    throw new HttpError(500, "Couldn't open that material. Try again.");
  }
  if (!material) {
    throw new HttpError(404, "That material isn't in your library.");
  }

  // Refusals below leave `status` untouched on purpose — a material we were
  // never able to read didn't fail to embed, it isn't embeddable.
  if (!material.storage_path) {
    // A bookmark, or a video saved before videos could be read. YouTube
    // videos now arrive with their captions stored as a .txt — the phone
    // fetches them, because YouTube refuses this server (D-037).
    throw new HttpError(
      400,
      material.source_type === 'video_link'
        ? 'This link has no transcript saved with it. Remove it and add the '
          + 'video again.'
        : "That material has no file to read. Upload it again.",
    );
  }

  const kind = fileKind(material.storage_path as string);
  if (kind === null) {
    throw new HttpError(
      400,
      'Only PDFs, photos (JPG, PNG, WebP, HEIC), .txt and .md files can be '
        + 'read right now.',
    );
  }

  if (material.status === 'processing' && !force) {
    // A second tap while the first run is in flight. Saying "already running"
    // beats embedding the same document twice.
    return json({ ok: true, alreadyRunning: true });
  }

  const { count: existing, error: countError } = await supa
    .from('material_chunks')
    .select('id', { count: 'exact', head: true })
    .eq('material_id', materialId);
  if (countError) {
    console.error('Could not count chunks', countError);
    throw new HttpError(500, "Couldn't open that material. Try again.");
  }

  if (material.status === 'embedded' && (existing ?? 0) > 0 && !force) {
    return json({ ok: true, chunks: existing ?? 0, alreadyEmbedded: true });
  }

  await setStatus(supa, materialId, 'processing');

  try {
    const { data: blob, error: downloadError } = await supa.storage
      .from('materials')
      .download(material.storage_path as string);

    if (downloadError || !blob) {
      console.error('Storage download failed', downloadError);
      throw new HttpError(
        404,
        "That file isn't in storage any more. Upload it again.",
      );
    }

    const bytes = new Uint8Array(await blob.arrayBuffer());
    const title = (material.title as string | null) ?? 'Study material';

    const sections = material.source_type === 'video_link'
      ? transcriptSections(bytes, title)
      : kind === 'text'
      ? textSections(bytes)
      : await visionSections(bytes, title, kind.mime);

    if (sections.length === 0) {
      throw new HttpError(
        422,
        "We couldn't read any text out of that file. If it's a scan, try a "
          + 'clearer copy.',
      );
    }

    const kept = sections.slice(0, MAX_CHUNKS);
    if (sections.length > kept.length) {
      console.warn(
        `Material ${materialId}: kept ${kept.length} of ${sections.length} sections`,
      );
    }

    const vectors = await embedTexts(
      kept.map((s) => documentText(s.unitLabel, s.text)),
    );

    // Delete first: this is what makes a retry idempotent rather than doubling
    // the chunk count. The two writes aren't in one transaction, so a crash
    // between them leaves zero chunks — which the status guard then refuses to
    // call `embedded`, so the row stays retryable instead of silently empty.
    const { error: clearError } = await supa
      .from('material_chunks')
      .delete()
      .eq('material_id', materialId);
    if (clearError) {
      console.error('Could not clear old chunks', clearError);
      throw new HttpError(500, "Couldn't save the results. Try again.");
    }

    const { error: insertError } = await supa.from('material_chunks').insert(
      kept.map((section, index) => ({
        user_id: userId,
        material_id: materialId,
        // A subject's syllabus (0027) passes its subject on, so the roadmap
        // can plan that subject from its own units; everything else is
        // subject-less, as before.
        subject_id: material.subject_id ?? null,
        unit_label: section.unitLabel,
        chunk_index: index,
        content: section.text,
        embedding: vectors[index],
      })),
    );
    if (insertError) {
      console.error('Could not insert chunks', insertError);
      throw new HttpError(500, "Couldn't save the results. Try again.");
    }

    await setStatus(supa, materialId, 'embedded');
    return json({ ok: true, chunks: kept.length });
  } catch (error) {
    // Best effort: the row has to end up somewhere the student can retry from,
    // and a failure to record the failure shouldn't replace the real reason.
    try {
      await setStatus(supa, materialId, 'failed');
    } catch (nested) {
      console.error('Could not mark material failed', nested);
    }
    throw error;
  }
});

/// Photos go through the same Gemini vision call as PDFs — handwritten notes
/// snapped on a phone are the most common study material there is.
const VISION_TYPES: Record<string, string> = {
  '.pdf': 'application/pdf',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.heic': 'image/heic',
  '.heif': 'image/heif',
};

/// `text`, a vision file with its MIME type, or null (unsupported).
function fileKind(path: string): 'text' | { mime: string } | null {
  const lower = path.toLowerCase();
  if (lower.endsWith('.txt') || lower.endsWith('.md')) return 'text';
  for (const [ext, mime] of Object.entries(VISION_TYPES)) {
    if (lower.endsWith(ext)) return { mime };
  }
  return null;
}

// deno-lint-ignore no-explicit-any
async function setStatus(
  supa: any,
  materialId: string,
  status: string,
): Promise<void> {
  // 0009_atomicity.sql narrowed the `authenticated` UPDATE grant to
  // (goal_id, title, status), so the caller's own token is enough here.
  const { error } = await supa
    .from('materials')
    .update({ status })
    .eq('id', materialId);
  if (error) {
    console.error(`Could not set status=${status}`, error);
    throw new HttpError(500, "Couldn't update that material. Try again.");
  }
}

/// Reads a PDF or a photo with Gemini's native document vision.
///
/// A Deno PDF parser was the alternative and was rejected: neither Deno nor
/// Docker is installed on this machine, so a parser could not be run even once
/// before deploying, and pdf.js under the Edge Runtime is a common crash.
async function visionSections(
  bytes: Uint8Array,
  title: string,
  mime: string,
): Promise<Section[]> {
  if (bytes.length > MAX_PDF_BYTES) {
    throw new HttpError(
      413,
      mime === 'application/pdf'
        ? 'That PDF is too large to read. Try one under 14 MB, or split it.'
        : 'That photo is too large to read. Try one under 14 MB.',
    );
  }

  const raw = await interact({
    systemInstruction: PDF_INSTRUCTION,
    schema: PDF_SCHEMA,
    // Transcription, not writing: nothing here should be invented.
    temperature: 0,
    input: [
      {
        type: 'text',
        text: `Transcribe this study material titled "${title}".`,
      },
      {
        type: 'document',
        data: encodeBase64(bytes),
        mime_type: mime,
      },
    ],
    // 120 sections of a few hundred words each. The model's ceiling is 65536,
    // and [sectionList] salvages whatever arrives if a document still outruns
    // this.
    maxOutputTokens: 48_000,
    // Reading a whole syllabus earns more of the worker's wall clock than a
    // chat reply does, but not so much that the worker is killed mid-write:
    // chunks and the status flip both still have to happen after this returns.
    budgetMs: 90_000,
  });

  const sections: Section[] = [];
  for (const entry of sectionList(raw)) {
    const text = typeof entry?.text === 'string' ? entry.text.trim() : '';
    if (text.length < 20) continue; // A heading on its own retrieves nothing.
    sections.push({
      unitLabel: cleanLabel(entry?.unit_label),
      text: text.slice(0, MAX_CHUNK_CHARS),
    });
  }
  return sections;
}

/// The section array, tolerating a reply that was cut off mid-stream.
///
/// A long document can hit the model's output-token limit, which truncates the
/// JSON and makes a strict parse throw — throwing away an otherwise good
/// transcription of everything before the cut. So on a parse failure, salvage
/// the complete objects rather than failing the whole material.
// deno-lint-ignore no-explicit-any
function sectionList(raw: string): any[] {
  try {
    const parsed = parseJsonObject(raw);
    return Array.isArray(parsed?.sections) ? parsed.sections : [];
  } catch (error) {
    const salvaged = salvageSections(raw);
    if (salvaged.length === 0) throw error;
    console.warn(`Salvaged ${salvaged.length} sections from a truncated reply`);
    return salvaged;
  }
}

// deno-lint-ignore no-explicit-any
function salvageSections(raw: string): any[] {
  // Every complete `{… "text": "…" …}` object, ignoring whatever the cut left
  // dangling after the last closing brace. Safe because the schema has no
  // nested objects.
  const objects = raw.match(/\{[^{}]*"text"\s*:\s*"(?:[^"\\]|\\.)*"[^{}]*\}/g)
    ?? [];
  // deno-lint-ignore no-explicit-any
  const out: any[] = [];
  for (const object of objects) {
    try {
      out.push(JSON.parse(object));
    } catch (_) {
      // Half an object at the cut. Nothing to recover from it.
    }
  }
  return out;
}

/// Splits plain text or Markdown locally — no model call needed, and none of the
/// transcription risk.
/// The heading text when [line] is a heading, else null.
function headingLabel(line: string): string | null {
  const markdown = /^#{1,6}\s+(.{1,80})$/.exec(line);
  if (markdown) return markdown[1].trim();
  if (
    line.length <= 80 &&
    /^(unit|chapter|module|topic|lecture|section|part)\s*[\divxlIVXL]+\b/i
      .test(line)
  ) {
    return line.replace(/[\s:.\-–—]+$/, '');
  }
  return null;
}

function textSections(bytes: Uint8Array): Section[] {
  if (bytes.length > MAX_TEXT_BYTES) {
    throw new HttpError(
      413,
      'That file is too large to read. Try one under 2 MB.',
    );
  }

  const text = new TextDecoder('utf-8', { fatal: false })
    .decode(bytes)
    .replace(/\r\n?/g, '\n');

  const sections: Section[] = [];
  let heading: string | null = null;
  let buffer = '';

  const flush = () => {
    const body = buffer.trim();
    buffer = '';
    if (body.length < 20) return;
    sections.push({ unitLabel: heading, text: body.slice(0, MAX_CHUNK_CHARS) });
  };

  for (const block of text.split(/\n\s*\n/)) {
    let trimmed = block.trim();
    if (trimmed.length === 0) continue;

    // A heading closes the current chunk and labels what follows — either a
    // Markdown heading, or a plain-text line like "Unit 3: Normalisation" or
    // "Chapter 2", which is how most typed notes mark their units. Without
    // unit labels a text file's chunks can't be told apart, which is what
    // `get_weak_topics` groups by.
    const lines = trimmed.split('\n');
    const label = headingLabel(lines[0].trim());
    if (label !== null) {
      flush();
      heading = label;
      trimmed = lines.slice(1).join('\n').trim();
      if (trimmed.length === 0) continue;
    }

    if (buffer.length + trimmed.length + 2 > TEXT_CHUNK_CHARS && buffer.length > 0) {
      const carry = buffer.slice(-TEXT_OVERLAP_CHARS);
      flush();
      // Repeat the tail of the last chunk so a sentence split across the
      // boundary is still findable from either side.
      buffer = carry.trimStart();
    }
    buffer += (buffer.length > 0 ? '\n\n' : '') + trimmed;
  }
  flush();

  return sections;
}

/// One caption line of a stored transcript: `[12:40] words`.
const TRANSCRIPT_LINE = /^\[(\d{1,2}(?::\d{2}){1,2})\]\s*(.*)$/;

/// About a minute and a half of speech. Larger than a notes chunk because
/// spoken text is thinner, and so that 120 chunks reach three hours of video.
const TRANSCRIPT_CHUNK_CHARS = 1500;

/// Splits a YouTube transcript — the file `YouTubeService.toFileText` writes on
/// the phone — on its timestamps, so each chunk says where in the video it
/// starts.
///
/// The label is "12:40 · Lecture title": the time leads so it survives being
/// cut short on a citation chip, and the title says which video when a whole
/// playlist is in the library. No model call — captions are already text.
function transcriptSections(bytes: Uint8Array, title: string): Section[] {
  if (bytes.length > MAX_TEXT_BYTES) {
    throw new HttpError(
      413,
      'That transcript is too long to read. Try a shorter video.',
    );
  }

  const lines: { at: string; text: string }[] = [];
  const text = new TextDecoder('utf-8', { fatal: false }).decode(bytes);
  for (const raw of text.split(/\r?\n/)) {
    const match = TRANSCRIPT_LINE.exec(raw.trim());
    const words = match?.[2].trim() ?? '';
    if (match && words.length > 0) lines.push({ at: match[1], text: words });
  }
  // Not a transcript after all; read it like any other text file.
  if (lines.length === 0) return textSections(bytes);

  const name = title.length > 50 ? `${title.slice(0, 49).trimEnd()}…` : title;
  const sections: Section[] = [];
  let parts: typeof lines = [];
  let size = 0;

  const flush = () => {
    const body = parts.map((p) => p.text).join(' ').trim();
    if (body.length < 20) return;
    sections.push({
      unitLabel: `${parts[0].at} · ${name}`,
      text: body.slice(0, MAX_CHUNK_CHARS),
    });
  };

  for (const line of lines) {
    if (size + line.text.length + 1 > TRANSCRIPT_CHUNK_CHARS && parts.length > 0) {
      flush();
      // Carry the last line or two, as the text splitter does, so a sentence
      // cut at the boundary is findable from either side. The next label
      // starts at the carried line, which is where its text really begins.
      const carry: typeof lines = [];
      let carried = 0;
      for (let i = parts.length - 1; i >= 0; i--) {
        if (carried + parts[i].text.length > TEXT_OVERLAP_CHARS) break;
        carry.unshift(parts[i]);
        carried += parts[i].text.length + 1;
      }
      parts = carry;
      size = carried;
    }
    parts.push(line);
    size += line.text.length + 1;
  }
  flush();

  return sections;
}

function cleanLabel(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim().replace(/\s+/g, ' ');
  if (trimmed.length === 0) return null;
  // `unit_label` is what the citation chip shows, so it stays short enough to
  // read on a phone.
  return trimmed.slice(0, 80);
}
