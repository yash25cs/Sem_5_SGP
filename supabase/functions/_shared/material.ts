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
