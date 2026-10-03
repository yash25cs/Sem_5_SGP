import { interact } from '../_shared/gemini.ts';
import { languageOf, languageRule } from '../_shared/language.ts';
import {
  loadMaterialSource,
  numberedSource,
  sampleChunks,
} from '../_shared/material.ts';
import { HttpError, json, readJson, requireUser, serve } from '../_shared/supa.ts';

/// Summarises one study material into concise bullet points.
///
/// Body: `{ materialId: string }`. The caller is taken from the JWT, never from
/// the body — see `requireUser`.

const SYSTEM_INSTRUCTION = `You summarise a student's study material into clear, concise bullet points.

Rules:
- Write 5 to 10 bullet points that capture the most important ideas, definitions, and takeaways from the excerpts.
- Each bullet is one or two sentences. No sub-bullets.
- Use the material's own terminology and notation.
- Do not add anything that isn't in the excerpts.
- No headings, no introduction, no conclusion. Just the bullets, each starting with •.`;

serve(async (req) => {
  const { supa, userId } = await requireUser(req);
  const body = await readJson(req);

  const materialId = typeof body.materialId === 'string'
    ? body.materialId.trim()
    : '';
  if (materialId.length === 0) {
    throw new HttpError(400, 'That request was malformed.');
  }

  const [source, lang] = await Promise.all([
    loadMaterialSource(supa, materialId),
    languageOf(supa, userId),
  ]);
  const chunks = sampleChunks(source.chunks);

  const answer = await interact({
    systemInstruction: SYSTEM_INSTRUCTION + languageRule(lang),
    temperature: 0.2,
    input: `Material: ${source.title}\n\nSummarize these excerpts.\n\n${numberedSource(chunks)}`,
    // Hindi and Gujarati script take roughly twice the tokens.
    maxOutputTokens: lang === 'en' ? 2048 : 4096,
    budgetMs: 30_000,
  });

  return json({ summary: answer, title: source.title });
});
