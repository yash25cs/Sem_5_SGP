import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import { corsHeaders, preflight } from './cors.ts';

/// An error that carries the HTTP status it should be answered with.
///
/// The message is written for a student, not a developer: `friendlyError` in
/// `lib/data/supabase_client.dart` surfaces `{"error": ...}` verbatim in a
/// snackbar, so anything vague here becomes a vague snackbar.
export class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = 'HttpError';
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/// The shape the Flutter client already knows how to read.
export function fail(status: number, message: string): Response {
  return json({ error: message }, status);
}

export interface Caller {
  supa: SupabaseClient;
  userId: string;
}

/// Identifies the caller from their JWT and returns a client that acts as them.
///
/// Deliberately *not* the service-role key: every table these functions touch
/// (`material_chunks`, `chat_messages`, `chat_citations`) is owner-insertable
/// under RLS, and `match_material_chunks` is security-invoker keyed on
/// `auth.uid()`. Forwarding the caller's token means the database enforces
/// ownership, so a `user_id` in the request body could never override it
/// (OWNERSHIP.md).
export async function requireUser(req: Request): Promise<Caller> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    throw new HttpError(401, 'Please sign in again.');
  }

  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!url || !anonKey) {
    // Both are injected by the Edge Runtime; missing means the function was
    // deployed into something that isn't a Supabase project.
    throw new HttpError(500, 'This function is misconfigured on the server.');
  }

  const supa = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await supa.auth.getUser();
  if (error || !data.user) {
    throw new HttpError(401, 'Your session has expired. Sign in again.');
  }
  return { supa, userId: data.user.id };
}

/// A client that bypasses RLS, for the two generators the schema forces.
///
/// `0008_rewards.sql` revokes `insert` on `milestones`, `milestone_tasks`,
/// `quizzes` and `quiz_questions` from `authenticated`, because all four are
/// XP-bearing if forged. Its own comment names the consequence: the generators
/// "must write with the `service_role` key after verifying the JWT, not by
/// forwarding the user's token". `generate-flashcards` needs none of this —
/// `insert on flashcards` is granted — so it keeps [requireUser]'s client.
///
/// The rule that keeps `OWNERSHIP.md` intact once this key is in the room: every
/// read and every ownership check still goes through [requireUser]'s client, and
/// every `user_id` written comes from [Caller.userId]. A `user_id` in the
/// request body is never read.
export function adminClient(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) {
    // Both are injected by the Edge Runtime, same as the anon key above.
    throw new HttpError(500, 'This function is misconfigured on the server.');
  }

  return createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/// Reads and shallow-validates the JSON body.
export async function readJson(req: Request): Promise<Record<string, unknown>> {
  try {
    const body = await req.json();
    if (body && typeof body === 'object' && !Array.isArray(body)) {
      return body as Record<string, unknown>;
    }
  } catch (_) {
    // Fall through — an unparseable body is the same problem as a wrong one.
  }
  throw new HttpError(400, 'That request was malformed.');
}

/// Wraps a handler with the preflight, the method check, and one place where
/// every thrown error becomes a response the app can show.
export function serve(handler: (req: Request) => Promise<Response>): void {
  Deno.serve(async (req) => {
    const pre = preflight(req);
    if (pre) return pre;

    if (req.method !== 'POST') {
      return fail(405, 'That request was malformed.');
    }

    try {
      return await handler(req);
    } catch (error) {
      if (error instanceof HttpError) {
        return fail(error.status, error.message);
      }
      // Unexpected: log the real thing for the dashboard, tell the student
      // something they can act on.
      console.error('Unhandled error', error);
      return fail(500, 'Something went wrong on our side. Try again shortly.');
    }
  });
}
