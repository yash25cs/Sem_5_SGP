import { HttpError, json, requireUser, serve, adminClient } from '../_shared/supa.ts';

/// Deletes a student's account and all associated data.
///
/// No body needed: caller identity is established entirely from the JWT via
/// `requireUser`.
///
/// Tables are deleted leaf-first so foreign-key constraints are never violated.
/// Each delete is wrapped in try/catch so a single failure doesn't abort the
/// whole cleanup.

serve(async (req) => {
  const { userId } = await requireUser(req);
  const admin = adminClient();

  // Delete all storage objects for this user in the materials bucket. Uploads
  // live flat under `<userId>/`. `list` returns one page (100 by default), so
  // keep removing pages until the folder is empty — each pass deletes what it
  // listed, so the next list starts from what's left.
  try {
    for (let pass = 0; pass < 50; pass++) {
      const { data: objects, error: listError } = await admin.storage
        .from('materials')
        .list(userId, { limit: 1000 });
      if (listError) {
        console.error('Could not list storage objects', listError);
        break;
      }
      if (!objects || objects.length === 0) break;

      const paths = objects.map((obj: { name: string }) => `${userId}/${obj.name}`);
      const { error: removeError } = await admin.storage
        .from('materials')
        .remove(paths);
      if (removeError) {
        console.error('Could not remove storage objects', removeError);
        break;
      }
    }
  } catch (e) {
    console.error('Error deleting storage objects', e);
  }

  // Leaf tables first, then parent tables. Order matters for FK constraints.
  const tables: Array<{ table: string; column: string }> = [
    // Citations reference chat_messages
    { table: 'chat_citations', column: 'user_id' },
    // Messages reference chat_threads
    { table: 'chat_messages', column: 'user_id' },
    { table: 'chat_threads', column: 'user_id' },
    // Quiz answers reference quiz_attempts, attempts reference quizzes
    { table: 'quiz_answers', column: 'user_id' },
    { table: 'quiz_attempts', column: 'user_id' },
    // Quiz questions reference quizzes
    { table: 'quiz_questions', column: 'user_id' },
    { table: 'quizzes', column: 'user_id' },
    // Flashcards reference flashcard_decks
    { table: 'flashcards', column: 'user_id' },
    { table: 'flashcard_decks', column: 'user_id' },
    // Chunks reference materials
    { table: 'material_chunks', column: 'user_id' },
    { table: 'materials', column: 'user_id' },
    // Milestone tasks reference milestones, daily_tasks reference goals
    { table: 'milestone_tasks', column: 'user_id' },
    { table: 'daily_tasks', column: 'user_id' },
    { table: 'milestones', column: 'user_id' },
    { table: 'subjects', column: 'user_id' },
    { table: 'goals', column: 'user_id' },
    // Gamification and study tracking
    { table: 'study_sessions', column: 'user_id' },
    { table: 'user_badges', column: 'user_id' },
    { table: 'streaks', column: 'user_id' },
    { table: 'activity_log', column: 'user_id' },
    // Profile last — many tables may FK to it
    { table: 'profiles', column: 'id' },
  ];

  for (const { table, column } of tables) {
    try {
      const { error } = await admin.from(table).delete().eq(column, userId);
      if (error) console.error(`Could not delete from ${table}`, error);
    } catch (e) {
      console.error(`Error deleting from ${table}`, e);
    }
  }

  // Delete the auth user last.
  try {
    const { error: authError } = await admin.auth.admin.deleteUser(userId);
    if (authError) {
      console.error('Could not delete auth user', authError);
      throw new HttpError(500, "Couldn't delete your account. Try again.");
    }
  } catch (e) {
    if (e instanceof HttpError) throw e;
    console.error('Error deleting auth user', e);
    throw new HttpError(500, "Couldn't delete your account. Try again.");
  }

  return json({ deleted: true });
});
