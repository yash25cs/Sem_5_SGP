import { encodeBase64 } from 'jsr:@std/encoding@1/base64';

import { interact, parseJsonObject } from '../_shared/gemini.ts';
import { HttpError, json, readJson, requireUser, serve } from '../_shared/supa.ts';

/// Reads a previous-year exam paper and records every question with its marks
/// and the syllabus unit it belongs to.
///
/// Body: `{ paperId: string }` — an `exam_papers` row the client created after
/// uploading the file. Acts as the caller throughout: nothing here pays XP, so
/// RLS on `exam_papers` and `paper_questions` is the whole boundary.
///
/// The units offered to the model are the student's own (distinct
/// `material_chunks.unit_label`s), so "Unit 3 asked 6 times" lines up with the
/// notes a mock exam is then written from.

const MAX_BYTES = 14 * 1024 * 1024;
const MAX_UNITS = 60;
const MAX_QUESTIONS = 80;
const MAX_TEXT = 4000;

const TYPES: Record<string, string> = {
  '.pdf': 'application/pdf',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.heic': 'image/heic',
  '.heif': 'image/heif',
};

const PAPER_SCHEMA = {
  type: 'object',
  properties: {
    year: { type: 'integer' },
    questions: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          number: { type: 'string' },
          text: { type: 'string' },
          marks: { type: 'number' },
          unit: { type: 'string' },
        },
        required: ['text'],
      },
    },
  },
  required: ['questions'],
};

const PAPER_INSTRUCTION = `You read a university exam question paper and list \
its questions.

Rules:
- List every question a student has to answer, in order. When a question has \
sub-parts that carry their own marks (1(a), 1(b)…), list each sub-part \
separately, with the parent's context folded into its text if it's needed to \
make sense.
- Skip instructions, cover pages, "attempt any five", and blank lines.
- number is the question number as printed, like "2(b)" or "Q5".
- text is the question, copied faithfully. Keep formulas readable as plain text.
- marks is the marks printed for that question or sub-part; leave it out when \
none is shown.
- unit is the ONE syllabus unit the question belongs to, copied exactly from \
the list you're given. If none fits, use "Other".
- year is the exam year printed on the paper, if there is one.`;

serve(async (req) => {
  const { supa, userId } = await requireUser(req);
  const body = await readJson(req);

  const paperId = typeof body.paperId === 'string' ? body.paperId.trim() : '';
  if (paperId.length === 0) {
    throw new HttpError(400, 'That request was malformed.');
  }

  const { data: paper, error: readError } = await supa
    .from('exam_papers')
    .select('id, title, year, storage_path')
    .eq('id', paperId)
    .maybeSingle();
  if (readError) {
    console.error('Could not read paper', readError);
    throw new HttpError(500, "Couldn't open that paper. Try again.");
  }
  if (!paper) throw new HttpError(404, "That paper isn't yours.");

  const path = String(paper.storage_path).toLowerCase();
  const mime = Object.entries(TYPES).find(([ext]) => path.endsWith(ext))?.[1];
  if (!mime) {
    throw new HttpError(400, 'Upload the paper as a PDF or a photo.');
  }

  await setStatus(supa, paperId, { status: 'analyzing', error: null });

  try {
    const { data: blob, error: downloadError } = await supa.storage
      .from('materials')
      .download(paper.storage_path);
    if (downloadError || !blob) {
      console.error('Storage download failed', downloadError);
      throw new HttpError(404, "That paper isn't in storage any more. Upload it again.");
    }
    const bytes = new Uint8Array(await blob.arrayBuffer());
    if (bytes.length > MAX_BYTES) {
      throw new HttpError(413, 'That file is too large. Try one under 14 MB.');
    }

    const units = await studentUnits(supa);

    const raw = await interact({
      systemInstruction: PAPER_INSTRUCTION,
      temperature: 0,
      schema: PAPER_SCHEMA,
      input: [
        {
          type: 'text',
          text: units.length > 0
            ? `The student's syllabus units:\n${units.map((u) => `- ${u}`).join('\n')}`
            : 'The student has no notes uploaded yet, so use "Other" for every unit.',
        },
        { type: 'document', data: encodeBase64(bytes), mime_type: mime },
      ],
      maxOutputTokens: 16_000,
      budgetMs: 90_000,
    });

    const parsed = parseJsonObject(raw);
    // deno-lint-ignore no-explicit-any
    const items: any[] = Array.isArray(parsed?.questions) ? parsed.questions : [];
    const byLower = new Map(units.map((u) => [u.toLowerCase(), u]));

    const questions = items
      .map((item) => {
        const text = str(item?.text).slice(0, MAX_TEXT);
        const marks = Number(item?.marks);
        const unit = byLower.get(str(item?.unit).toLowerCase()) ?? null;
        return {
          user_id: userId,
          paper_id: paperId,
          question_no: str(item?.number).slice(0, 20) || null,
          text,
          marks: Number.isFinite(marks) && marks > 0 && marks <= 100 ? marks : null,
          unit_label: unit,
        };
      })
      .filter((q) => q.text.length >= 8)
      .slice(0, MAX_QUESTIONS);

    if (questions.length === 0) {
      throw new HttpError(
        422,
        "We couldn't find any questions in that file. Try a clearer copy.",
      );
    }

    // Re-analysing replaces, so a retry never doubles the counts.
    await supa.from('paper_questions').delete().eq('paper_id', paperId);
    const { error: insertError } = await supa.from('paper_questions').insert(questions);
    if (insertError) {
      console.error('Could not save questions', insertError);
      throw new HttpError(500, "Couldn't save the questions. Try again.");
    }

    const year = Number(parsed?.year);
    await setStatus(supa, paperId, {
      status: 'analyzed',
      question_count: questions.length,
      ...(paper.year == null && Number.isInteger(year) && year >= 1990 && year <= 2100
        ? { year }
        : {}),
    });

    return json({
      questions: questions.length,
      mapped: questions.filter((q) => q.unit_label !== null).length,
    });
  } catch (error) {
    const message = error instanceof HttpError
      ? error.message
      : "Couldn't read that paper. Try again.";
    await setStatus(supa, paperId, { status: 'failed', error: message })
      .catch(() => {});
    throw error;
  }
});

/// The student's own unit headings, most-used first.
// deno-lint-ignore no-explicit-any
async function studentUnits(supa: any): Promise<string[]> {
  const { data } = await supa
    .from('material_chunks')
    .select('unit_label')
    .not('unit_label', 'is', null)
    .limit(2000);
  const counts = new Map<string, number>();
  for (const row of data ?? []) {
    const label = str(row.unit_label);
    if (label) counts.set(label, (counts.get(label) ?? 0) + 1);
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, MAX_UNITS)
    .map(([label]) => label);
}

// deno-lint-ignore no-explicit-any
async function setStatus(supa: any, paperId: string, fields: Record<string, unknown>) {
  const { error } = await supa.from('exam_papers').update(fields).eq('id', paperId);
  if (error) console.error('Could not update paper status', error);
}

function str(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}
