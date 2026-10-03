import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import { HttpError } from './supa.ts';

/// Reading one material's ingested text, shared by `generate-quiz` and
/// `generate-flashcards`.
///
/// Both generate from a file the student named, so there is nothing to search
/// *for*: the chunks are read by `material_id` in document order rather than
/// through `match_material_chunks`. That is cheaper (no query embedding), it is
/// deterministic, and it sees the whole document instead of the six best
/// fragments. It also sidesteps a live gap — `embed-material` writes
/// `subject_id: null` on every chunk, so subject-scoped retrieval matches
/// nothing today.

export interface Chunk {
  id: string;
  unitLabel: string | null;
  content: string;
}

export interface MaterialSource {
  title: string;
  chunks: Chunk[];
}

/// How much material text one generation call may see.
///
/// `gemini-3.5-flash-lite` takes far more than this, but the whole call runs
/// under a deadline (D-015) and prompt size is what that deadline is spent on.
/// 60k characters is roughly a 25-page chapter — enough that a 15-question quiz
/// isn't drawn from one section.
export const MAX_SOURCE_CHARS = 60_000;

/// Per-excerpt ceiling, so one enormous section can't crowd out the rest.
const MAX_CHUNK_CHARS = 8_000;

/// Verifies the material belongs to the caller, then reads its chunks in
/// document order.
///
/// [supa] must be the caller's own client: RLS turns "not yours" into "not
/// found", which is the honest answer anyway and is what keeps a guessed
/// `materialId` from reaching another student's notes.
export async function loadMaterialSource(
  supa: SupabaseClient,
  materialId: string,
): Promise<MaterialSource> {
  const { data: material, error: materialError } = await supa
    .from('materials')
    .select('id, title, status')
    .eq('id', materialId)
    .maybeSingle();
  if (materialError) {
    console.error('Could not read material', materialError);
    throw new HttpError(500, "Couldn't open that file. Try again.");
  }
  if (!material) {
    throw new HttpError(404, "That file isn't yours.");
  }

  const { data: rows, error: chunkError } = await supa
    .from('material_chunks')
    .select('id, unit_label, content')
    .eq('material_id', materialId)
    .order('chunk_index', { ascending: true });
  if (chunkError) {
    console.error('Could not read chunks', chunkError);
    throw new HttpError(500, "Couldn't read that file. Try again.");
  }

  const chunks: Chunk[] = (rows ?? [])
    .map((row) => ({
      id: String(row.id),
      unitLabel: typeof row.unit_label === 'string' && row.unit_label.trim()
        ? row.unit_label.trim()
        : null,
      content: String(row.content ?? '').trim(),
    }))
    .filter((chunk) => chunk.content.length > 0);

  if (chunks.length === 0) {
    // `status` says which of the two this is: never read, or read and empty.
    throw new HttpError(
      400,
      material.status === 'embedded'
        ? "There's no readable text in that file."
        : "That file hasn't been read yet. Retry it from your materials first.",
    );
  }

  const title = typeof material.title === 'string' && material.title.trim()
    ? material.title.trim()
    : 'Your material';

  return { title, chunks };
}

/// The student's weakest units, as generation source.
///
/// Reads `get_weak_topics` through the caller's client, then each topic's own
/// chunks. `materialId` is set when every topic comes from one file, so a
/// generated quiz can still say which material it covers.
export interface WeakSource extends MaterialSource {
  materialId: string | null;
  units: string[];
}

export async function loadWeakSource(
  supa: SupabaseClient,
  limit = 3,
): Promise<WeakSource> {
  const { data: topics, error } = await supa.rpc('get_weak_topics', {
    p_limit: limit,
  });
  if (error) {
    console.error('Could not rank weak topics', error);
    throw new HttpError(500, "Couldn't work out your weak spots. Try again.");
  }
  // deno-lint-ignore no-explicit-any
  const rows: any[] = Array.isArray(topics) ? topics : [];
  if (rows.length === 0) {
    throw new HttpError(
      404,
      'No weak spots yet. Take a quiz or review some cards first.',
    );
  }

  const chunks: Chunk[] = [];
  for (const topic of rows) {
    // A null label is a file without unit headings, taken as one topic.
    let query = supa
      .from('material_chunks')
      .select('id, unit_label, content')
      .eq('material_id', topic.material_id);
    query = topic.unit_label === null
      ? query.is('unit_label', null)
      : query.eq('unit_label', topic.unit_label);
    const { data } = await query.order('chunk_index', { ascending: true });
    for (const row of data ?? []) {
      const content = String(row.content ?? '').trim();
      if (content.length === 0) continue;
      chunks.push({
        id: String(row.id),
        unitLabel: typeof row.unit_label === 'string' ? row.unit_label : null,
        content,
      });
    }
  }
  if (chunks.length === 0) {
    throw new HttpError(
      404,
      "Your weak spots' notes aren't available any more. Upload them again.",
    );
  }

  const materials = new Set(rows.map((t) => String(t.material_id)));
  const units = rows.map((t) => String(t.unit_label ?? t.material_title));
  return {
    title: `Weak spots: ${units.join(', ')}`.slice(0, 120),
    chunks,
    materialId: materials.size === 1 ? [...materials][0] : null,
    units,
  };
}

/// A mock exam's source: notes for the units past papers ask about most, each
/// given room in proportion to how often it's asked, plus a few real past
/// questions so the new ones match the exam's style and emphasis.
export interface MockSource extends MaterialSource {
  examples: string[];
  papers: number;
}

export async function loadMockSource(
  supa: SupabaseClient,
  maxChars = 40_000,
): Promise<MockSource> {
  const { data: topics, error } = await supa.rpc('get_exam_topics', {
    p_limit: 8,
  });
  if (error) {
    console.error('Could not rank exam topics', error);
    throw new HttpError(500, "Couldn't read your past papers. Try again.");
  }
  // deno-lint-ignore no-explicit-any
  const ranked = ((topics ?? []) as any[]).filter((t) => t.unit_label !== 'Other');
  if (ranked.length === 0) {
    throw new HttpError(
      404,
      'Upload a past paper first — and your notes, so its questions can be '
        + 'matched to your units.',
    );
  }

  const asked = ranked.reduce((sum, t) => sum + Number(t.times_asked), 0);
  const chunks: Chunk[] = [];
  for (const topic of ranked) {
    const budget = Math.max(3_000, (maxChars * Number(topic.times_asked)) / asked);
    const { data } = await supa
      .from('material_chunks')
      .select('id, unit_label, content')
      .eq('unit_label', topic.unit_label)
      .order('chunk_index', { ascending: true });
    const own: Chunk[] = (data ?? [])
      .map((row) => ({
        id: String(row.id),
        unitLabel: typeof row.unit_label === 'string' ? row.unit_label : null,
        content: String(row.content ?? '').trim(),
      }))
      .filter((c) => c.content.length > 0);
    chunks.push(...sampleChunks(own, budget));
  }
  if (chunks.length === 0) {
    throw new HttpError(
      404,
      "Your notes for the most-asked units aren't uploaded yet.",
    );
  }

  const { data: examples } = await supa
    .from('paper_questions')
    .select('text')
    .in('unit_label', ranked.map((t) => t.unit_label))
    .order('marks', { ascending: false, nullsFirst: false })
    .limit(8);

  const papers = Math.max(...ranked.map((t) => Number(t.papers) || 0));
  return {
    title: `Mock exam from ${papers} past paper${papers === 1 ? '' : 's'}`,
    chunks,
    examples: (examples ?? []).map((e) => String(e.text).slice(0, 400)),
    papers,
  };
}

/// Trims a document to [maxChars] by sampling evenly across it.
///
/// Deliberately not a head truncation: a 15-question quiz drawn from the first
/// 60k characters of a 300-page book is a quiz about chapter 1. Keeping every
/// n-th section instead means the questions span the material the student
/// actually has to revise.
export function sampleChunks(
  chunks: Chunk[],
  maxChars = MAX_SOURCE_CHARS,
): Chunk[] {
  const total = chunks.reduce((sum, chunk) => sum + chunk.content.length, 0);
  if (total <= maxChars) return chunks;

  // How many average-sized sections fit, and therefore how far apart the kept
  // ones should be.
  const keep = Math.max(1, Math.floor((chunks.length * maxChars) / total));
  const stride = chunks.length / keep;

  const picked: Chunk[] = [];
  const seen = new Set<string>();
  let used = 0;
  for (let i = 0; i < keep; i++) {
    const chunk = chunks[Math.min(chunks.length - 1, Math.round(i * stride))];
    if (!chunk || seen.has(chunk.id)) continue;
    if (picked.length > 0 && used + chunk.content.length > maxChars) break;
    picked.push(chunk);
    seen.add(chunk.id);
    used += chunk.content.length;
  }

  // One section longer than the whole budget: keep its opening rather than
  // returning nothing to generate from.
  if (picked.length === 1 && picked[0].content.length > maxChars) {
    return [{ ...picked[0], content: picked[0].content.slice(0, maxChars) }];
  }
  return picked;
}

/// Numbers the excerpts so the model can point back at one.
///
/// The number is an index into the same array, which is how a generated card
/// gets a real `source_chunk_id` instead of a guess.
export function numberedSource(chunks: Chunk[]): string {
  return chunks
    .map((chunk, index) => {
      const label = chunk.unitLabel ?? 'Untitled section';
      return `[${index + 1}] ${label}\n${
        chunk.content.slice(0, MAX_CHUNK_CHARS)
      }`;
    })
    .join('\n\n');
}
