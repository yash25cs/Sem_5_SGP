import { interact } from '../_shared/gemini.ts';
import { languageOf, languageRule } from '../_shared/language.ts';
import {
  loadMaterialSource,
  numberedSource,
  sampleChunks,
} from '../_shared/material.ts';
import { HttpError, json, readJson, requireUser, serve } from '../_shared/supa.ts';

/// A one-page revision sheet for one unit of a study material: the key ideas,
/// definitions, formulas, likely exam questions and common mistakes — what a
/// student reads the night before the paper.
///
/// Body: `{ materialId: string, unitLabel?: string }`. Without a unit, or with
/// one the file doesn't have, the sheet covers the whole file. The unit's past
/// paper questions, when the student has uploaded any, steer the "likely
/// questions" section. The caller is taken from the JWT, never from the body —
/// see `requireUser`.

const SYSTEM_INSTRUCTION = `You write a one-page revision sheet from a student's study material, for reading the night before the exam.

Write these sections, in this order. Start each with a line "## " and its name, then bullets each starting with "• ":
## Key ideas — 4 to 7 bullets, the ideas the rest of the unit hangs on.
## Definitions — 3 to 8 bullets, each "term: meaning" in one line.
## Formulas and rules — only if the excerpts contain formulas, laws, algorithms or syntax worth memorising; otherwise leave the whole section out.
## Likely exam questions — 3 to 5 questions. When past paper questions are given, base them on those; otherwise on what the excerpts stress most.
## Common mistakes — 2 to 4 bullets on what students typically confuse or forget here.

Rules:
- Everything must come from the excerpts. Add nothing that isn't in them.
- Use the material's own terminology and notation.
- Short bullets: one line each where possible. The whole sheet must fit on one printed page, about 350 words.
- No introduction, no conclusion, nothing outside the sections.`;

/// Past questions the model sees, most marks first.
const MAX_QUESTIONS = 6;

serve(async (req) => {
  const { supa, userId } = await requireUser(req);
  const body = await readJson(req);

  const materialId = typeof body.materialId === 'string'
    ? body.materialId.trim()
    : '';
  const unitLabel = typeof body.unitLabel === 'string'
    ? body.unitLabel.trim().slice(0, 200)
    : '';
  if (materialId.length === 0) {
    throw new HttpError(400, 'That request was malformed.');
  }

  const [source, lang] = await Promise.all([
    loadMaterialSource(supa, materialId),
    languageOf(supa, userId),
  ]);

  const wanted = unitLabel.toLowerCase();
  const unitChunks = wanted.length === 0
    ? []
    : source.chunks.filter((c) => (c.unitLabel ?? '').toLowerCase() === wanted);
  const covering = unitChunks.length > 0 ? unitLabel : null;
  // One unit is short enough to send whole; a whole file is sampled.
  const chunks = sampleChunks(unitChunks.length > 0 ? unitChunks : source.chunks);

  const questions = covering === null ? [] : await pastQuestions(supa, covering);

  const parts = [
    `Material: ${source.title}`,
    covering === null ? 'Cover the whole material.' : `Unit: ${covering}`,
  ];
  if (questions.length > 0) {
    parts.push(
      'Past paper questions on this unit:\n'
        + questions.map((q) => `- ${q}`).join('\n'),
    );
  }
  parts.push(`Excerpts:\n\n${numberedSource(chunks)}`);

  const sheet = await interact({
    systemInstruction: SYSTEM_INSTRUCTION + languageRule(lang),
    temperature: 0.2,
    input: parts.join('\n\n'),
    // Hindi and Gujarati script take roughly twice the tokens.
    maxOutputTokens: lang === 'en' ? 2048 : 4096,
    budgetMs: 40_000,
  });

  return json({
    sheet: sheet.trim(),
    title: source.title,
    unit: covering,
    pastQuestions: questions.length,
  });
});

/// The student's own past paper questions on [unit], most marks first. Through
/// the caller's client, so RLS keeps it to their papers. Empty on failure: a
/// sheet without them is still a sheet.
// deno-lint-ignore no-explicit-any
async function pastQuestions(supa: any, unit: string): Promise<string[]> {
  const { data, error } = await supa
    .from('paper_questions')
    .select('text, marks')
    .eq('unit_label', unit)
    .order('marks', { ascending: false, nullsFirst: false })
    .limit(MAX_QUESTIONS);
  if (error) {
    console.error('Could not read past questions', error);
    return [];
  }
  return (data ?? [])
    .map((row: { text?: unknown }) => String(row.text ?? '').trim().slice(0, 400))
    .filter((text: string) => text.length > 0);
}
