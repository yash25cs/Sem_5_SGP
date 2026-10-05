import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import { interact, parseJsonObject } from '../_shared/gemini.ts';
import {
  adminClient,
  HttpError,
  json,
  readJson,
  requireUser,
  serve,
} from '../_shared/supa.ts';

/// Writes a week-by-week roadmap for one goal.
///
/// Body: `{ goalId: string }`. The caller is taken from the JWT, never from the
/// body — see `requireUser`.
///
/// Unlike the quiz and card generators this reads no chunk bodies: a roadmap is
/// goal-shaped, so its input is the goal itself (name, exam date, pace), its
/// subjects, and the *headings* of whatever the student has uploaded. Headings
/// are enough to plan around and cost almost nothing to send. A student who has
/// uploaded nothing still gets a plan from their subject names.
///
/// Two clients: reads and the ownership check use the caller's own token, and
/// only the writes use `adminClient()`, because `0008_rewards.sql` revokes
/// `insert on milestones, milestone_tasks` from `authenticated` — a roadmap of
/// pre-ticked tasks would report 100% progress. `user_id` still comes from the
/// JWT.

/// Weeks the plan may span. Two is the shortest thing worth calling a roadmap;
/// past twelve a student is reading a plan for a semester they haven't started.
const MIN_WEEKS = 2;
const MAX_WEEKS = 12;
const DEFAULT_WEEKS = 6;

/// Pace-based fallback lengths, matching `set_target_screen.dart`'s
/// `_estimatedDays` so the roadmap is the length the student was promised.
const PACE_DAYS: Record<string, number> = {
  relaxed: 45,
  steady: 30,
  intense: 21,
};

/// Longest plan we'll record in `goals.roadmap_days`. An exam two years out is
/// a date-picker slip, and `create_goal` deliberately doesn't refuse it
/// ("the roadmap generator clamps, it doesn't refuse").
const MAX_ROADMAP_DAYS = 180;

/// Headings sent to the model. Enough to cover a semester's uploads — a
/// 92-lecture playlist included — without turning the prompt into a table of
/// contents.
const MAX_UNIT_LABELS = 120;

/// Units listed per subject from its syllabus. A semester syllabus is
/// usually 5–8 units; past this it's the reader splitting one unit up.
const MAX_SYLLABUS_UNITS = 15;

/// Rows scanned to collect those headings. Chunks repeat their unit label, so
/// this is a bound on work, not on coverage.
const LABEL_SCAN_ROWS = 600;

/// The "12:40 · " a video chunk's label starts with (D-037).
const VIDEO_STAMP_PATTERN = '^[0-9]{1,2}(:[0-9]{2}){1,2} · ';

/// Lectures listed from one library — a playlist holds at most 100.
const MAX_VIDEO_TITLES = 100;

/// Below this it isn't a plan.
const MIN_MILESTONES = 2;

/// Tasks per week that a student will actually read.
const MAX_TASKS_PER_MILESTONE = 6;

const ROADMAP_SCHEMA = {
  type: 'object',
  properties: {
    milestones: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          tasks: { type: 'array', items: { type: 'string' } },
        },
        required: ['title', 'tasks'],
      },
    },
  },
  required: ['milestones'],
};

const ROADMAP_INSTRUCTION = `You plan a student's revision as weekly milestones.

Rules:
- One milestone per week, in order, for exactly the number of weeks asked for. \
The week each one belongs to is its position in the list, so do not number them \
in the title.
- title says what that week achieves, in the student's own subjects and units — \
"Finish DBMS normalisation and indexing", not "Study hard".
- tasks are 3 to 5 concrete actions for that week, each one sitting a student \
down at a desk: read a named unit, work practice problems on a named topic, \
revise a named definition, take a practice test. No task longer than 90 \
characters.
- Cover every subject across the plan and weight the ones with more units more \
heavily. Do not spend a whole week on something the student has one heading for.
- Build up: understand first, then practise, then revise. Leave the last week \
for revision and mock tests.
- Plan only from the subjects and unit headings given. Invent no topics.
- When subjects have their own exam dates, each subject must be fully covered \
and revised before its own exam: schedule it earlier, give the week of its \
exam to revising it, and stop scheduling it after that week.
- When a subject lists its syllabus units, those are what its exam covers: \
plan that subject from exactly those units, in that order, and name them in \
its tasks.`;

interface Milestone {
  weekLabel: string;
  title: string;
  tasks: string[];
}

serve(async (req) => {
  const { supa, userId } = await requireUser(req);
  const body = await readJson(req);

  const goalId = typeof body.goalId === 'string' ? body.goalId.trim() : '';
  if (goalId.length === 0) {
    throw new HttpError(400, 'That request was malformed.');
  }

  // RLS turns "not yours" into "not found", which is the honest answer anyway.
  const { data: goal, error: goalError } = await supa
    .from('goals')
    .select('id, name, exam_date, pace, roadmap_days')
    .eq('id', goalId)
    .maybeSingle();
  if (goalError) {
    console.error('Could not read goal', goalError);
    throw new HttpError(500, "Couldn't open that goal. Try again.");
  }
  if (!goal) {
    throw new HttpError(404, "That goal isn't yours.");
  }

  const { data: subjectRows, error: subjectError } = await supa
    .from('subjects')
    .select('id, name, exam_date')
    .eq('goal_id', goalId)
    .order('exam_date', { ascending: true, nullsFirst: false })
    .order('name', { ascending: true });
  if (subjectError) {
    console.error('Could not read subjects', subjectError);
    throw new HttpError(500, "Couldn't read your subjects. Try again.");
  }

  // "DBMS (exam 2026-11-20, in week 2)" when the subject has its own paper
  // date, so the plan finishes each subject before its exam rather than the
  // last one. The week is spelled out: a date alone left the model revising a
  // subject the week after its exam.
  const today = Date.UTC(
    new Date().getUTCFullYear(),
    new Date().getUTCMonth(),
    new Date().getUTCDate(),
  );
  // A subject with its own syllabus (0027) brings its units along:
  // "DBMS (exam …) — syllabus units: ER model; Normalisation; SQL".
  const syllabi = await syllabusUnits(supa);
  const subjects = (subjectRows ?? [])
    .map((row) => {
      const name = String(row.name ?? '').trim();
      if (name.length === 0) return name;
      const units = syllabi.get(String(row.id)) ?? [];
      const syllabus = units.length > 0
        ? ` — syllabus units: ${units.join('; ')}`
        : '';
      if (typeof row.exam_date !== 'string') return name + syllabus;
      const days = (Date.parse(row.exam_date) - today) / 86_400_000;
      const week = Math.max(1, Math.ceil(days / 7));
      return `${name} (exam ${row.exam_date}, in week ${week}; `
        + `nothing on it after week ${week})${syllabus}`;
    })
    .filter((name) => name.length > 0);

  if (subjects.length === 0) {
    throw new HttpError(
      400,
      'Add at least one subject to your goal first, then generate a roadmap.',
    );
  }

  const units = await unitLabels(supa);
  const days = roadmapDays(goal.exam_date, goal.pace);
  const weeks = weekCount(days);

  const raw = await interact({
    systemInstruction: ROADMAP_INSTRUCTION,
    // A plan is structure, not prose; near-zero keeps it from wandering off the
    // subjects it was given.
    temperature: 0.2,
    schema: ROADMAP_SCHEMA,
    input: buildPrompt(String(goal.name ?? '').trim(), subjects, units, weeks,
      days, goal.exam_date),
    maxOutputTokens: 900 + weeks * 400,
    // Shorter than the quiz's 60 s: this prompt carries headings, not chunk
    // bodies, so a call that hasn't answered by now is one that won't.
    budgetMs: 45_000,
  });

  const parsed = parseJsonObject(raw);
  // deno-lint-ignore no-explicit-any
  const items: any[] = Array.isArray(parsed?.milestones) ? parsed.milestones : [];
  const milestones = keepValid(items).slice(0, MAX_WEEKS);

  if (milestones.length < MIN_MILESTONES) {
    console.error(
      `Only ${milestones.length} of ${items.length} milestones were usable for `
        + `goal ${goalId}`,
    );
    throw new HttpError(
      502,
      "The AI couldn't build a roadmap from that goal. Try again.",
    );
  }

  const admin = adminClient();

  // Regenerating replaces: the old plan's weeks would otherwise interleave with
  // the new one's and every task would be listed twice. The FK cascade takes
  // `milestone_tasks` with them, which is why the client's revoked DELETE on
  // that table doesn't block this.
  const { error: clearError } = await admin
    .from('milestones')
    .delete()
    .eq('goal_id', goalId)
    .eq('user_id', userId);
  if (clearError) {
    console.error('Could not clear the old roadmap', clearError);
    throw new HttpError(500, "Couldn't replace your roadmap. Try again.");
  }

  const { data: saved, error: insertError } = await admin
    .from('milestones')
    .insert(milestones.map((milestone, index) => ({
      user_id: userId,
      goal_id: goalId,
      week_label: milestone.weekLabel,
      title: milestone.title,
      // The first week is what the student is on now; the rest are ahead of
      // them. `state` is the one milestone column the app may update, so this is
      // a starting position, not a verdict.
      state: index === 0 ? 'active' : 'upcoming',
      order_index: index,
      // `color_key` stays null on purpose: `subject_style.dart` falls back to a
      // stable palette keyed on the row, so a generator picking colours would
      // only fight it.
    })))
    .select('id, order_index');
  if (insertError || !saved || saved.length === 0) {
    console.error('Could not save the roadmap', insertError);
    throw new HttpError(500, "Couldn't save your roadmap. Try again.");
  }

  // Match on `order_index` rather than trusting the returned row order.
  const idByOrder = new Map<number, string>(
    saved.map((row) => [Number(row.order_index), String(row.id)]),
  );

  const taskRows = milestones.flatMap((milestone, index) => {
    const milestoneId = idByOrder.get(index);
    if (!milestoneId) return [];
    return milestone.tasks.map((name, taskIndex) => ({
      user_id: userId,
      milestone_id: milestoneId,
      name,
      order_index: taskIndex,
      // `done` takes its default false — a pre-ticked task is exactly the
      // forgery the insert revokes exist to prevent.
    }));
  });

  const { error: taskError } = await admin
    .from('milestone_tasks')
    .insert(taskRows);
  if (taskError) {
    console.error('Could not save the roadmap tasks', taskError);
    // Milestones with no tasks would render as empty weeks the student can't
    // tick, so they go back out with the failure.
    await admin
      .from('milestones')
      .delete()
      .in('id', [...idByOrder.values()]);
    throw new HttpError(500, "Couldn't save your roadmap. Try again.");
  }

  // The roadmap counters are this function's to set — `0008_rewards.sql` revokes
  // them from the client for that reason. `current_day` restarts because the
  // plan the student is on day 12 of no longer exists, and the start date is
  // what `get_roadmap_pace` measures "behind" from.
  const { error: goalUpdateError } = await admin
    .from('goals')
    .update({
      roadmap_days: days,
      current_day: 1,
      roadmap_started_on: new Date().toISOString().slice(0, 10),
    })
    .eq('id', goalId)
    .eq('user_id', userId);
  // Cosmetic next to a saved roadmap: Home's "Day 3 / 30" line hides itself
  // when `roadmap_days` is null.
  if (goalUpdateError) {
    console.error('Could not update the goal counters', goalUpdateError);
  }

  return json({
    milestones: milestones.length,
    tasks: taskRows.length,
    weeks,
    days,
  });
});

/// The distinct unit headings across everything the student has uploaded:
/// the units of their files, then one heading per YouTube lecture.
///
/// Videos are read by title rather than from their chunks. Each chunk of a
/// video is labelled "12:40 · Lecture title" (D-037) — right for a citation,
/// but here it would be dozens of near-identical headings per lecture, and at
/// ~25 chunks a video the 600-row scan would reach only the first two dozen
/// lectures of a long playlist.
///
/// Read through the caller's client, so RLS scopes it to their own materials.
/// Failure is not fatal — headings sharpen the plan, subject names alone still
/// produce one.
async function unitLabels(supa: SupabaseClient): Promise<string[]> {
  const [chunks, videos] = await Promise.all([
    supa
      .from('material_chunks')
      .select('unit_label')
      .not('unit_label', 'is', null)
      .not('unit_label', 'match', VIDEO_STAMP_PATTERN)
      .order('material_id', { ascending: true })
      .order('chunk_index', { ascending: true })
      .limit(LABEL_SCAN_ROWS),
    supa
      .from('materials')
      .select('title')
      .eq('source_type', 'video_link')
      .eq('status', 'embedded')
      .order('created_at', { ascending: true })
      .limit(MAX_VIDEO_TITLES),
  ]);
  if (chunks.error) console.error('Could not read unit labels', chunks.error);
  if (videos.error) console.error('Could not read video titles', videos.error);

  const seen = new Set<string>();
  const labels: string[] = [];
  const all = [
    ...(chunks.data ?? []).map((row) => row.unit_label),
    ...(videos.data ?? []).map((row) => row.title),
  ];
  for (const value of all) {
    const label = String(value ?? '').trim().slice(0, 80);
    if (label.length === 0 || seen.has(label.toLowerCase())) continue;
    seen.add(label.toLowerCase());
    labels.push(label);
    if (labels.length >= MAX_UNIT_LABELS) break;
  }
  return labels;
}

/// How long the plan runs, in days: to the exam if there is one, otherwise the
/// pace default the student was shown at goal creation.
function roadmapDays(examDate: unknown, pace: unknown): number {
  const paceDays = PACE_DAYS[String(pace ?? 'steady')] ?? PACE_DAYS.steady;

  if (typeof examDate !== 'string' || examDate.length === 0) return paceDays;
  const exam = new Date(`${examDate}T00:00:00Z`);
  if (Number.isNaN(exam.getTime())) return paceDays;

  const now = new Date();
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const days = Math.ceil((exam.getTime() - today) / 86_400_000);

  // A past exam date means the plan is for revising anyway, so it gets the pace
  // default rather than a refusal.
  if (days < 1) return paceDays;
  return Math.min(days, MAX_ROADMAP_DAYS);
}

function weekCount(days: number): number {
  const weeks = Math.ceil(days / 7);
  if (!Number.isFinite(weeks)) return DEFAULT_WEEKS;
  return Math.min(MAX_WEEKS, Math.max(MIN_WEEKS, weeks));
}

function buildPrompt(
  goalName: string,
  subjects: string[],
  units: string[],
  weeks: number,
  days: number,
  examDate: unknown,
): string {
  const parts: string[] = [
    `Goal: ${goalName.length > 0 ? goalName : 'Exam preparation'}`,
    typeof examDate === 'string' && examDate.length > 0
      ? `Exam date: ${examDate} (about ${days} days away)`
      : `No exam date set; plan for about ${days} days`,
    `Subjects: ${subjects.join(', ')}`,
  ];

  parts.push(
    units.length > 0
      ? `Unit headings from the material this student uploaded:\n`
        + units.map((unit) => `- ${unit}`).join('\n')
      : 'This student has not uploaded any material yet, so plan from the '
        + 'subject names alone and keep the tasks general.',
  );

  parts.push(`Write exactly ${weeks} weekly milestones.`);
  return parts.join('\n\n');
}

/// Each subject's syllabus units, in document order, keyed by subject id —
/// the headings of the chunks a subject's syllabus became (0027). Through the
/// caller's client, so RLS keeps it to their own. Empty on failure: the plan
/// still has the subject names and the library's headings.
async function syllabusUnits(supa: SupabaseClient): Promise<Map<string, string[]>> {
  const { data, error } = await supa
    .from('material_chunks')
    .select('subject_id, unit_label')
    .not('subject_id', 'is', null)
    .not('unit_label', 'is', null)
    .order('material_id', { ascending: true })
    .order('chunk_index', { ascending: true })
    .limit(LABEL_SCAN_ROWS);
  if (error) console.error('Could not read syllabus units', error);

  const bySubject = new Map<string, string[]>();
  for (const row of data ?? []) {
    const label = String(row.unit_label ?? '').trim().slice(0, 80);
    if (label.length === 0) continue;
    const key = String(row.subject_id);
    const units = bySubject.get(key) ?? [];
    if (units.length >= MAX_SYLLABUS_UNITS) continue;
    if (!units.some((u) => u.toLowerCase() === label.toLowerCase())) units.push(label);
    bySubject.set(key, units);
  }
  return bySubject;
}

/// Keeps the milestones worth storing.
///
/// A milestone with no tasks renders as a week the student can't tick, and
/// `recompute_goal_progress` counts tasks — so an empty one would dilute the
/// percentage it contributes nothing to.
// deno-lint-ignore no-explicit-any
function keepValid(items: any[]): Milestone[] {
  const kept: Milestone[] = [];

  for (const item of items) {
    const title = text(item?.title).slice(0, 160);
    if (title.length === 0) continue;

    const tasks: string[] = [];
    const seen = new Set<string>();
    for (const raw of Array.isArray(item?.tasks) ? item.tasks : []) {
      const task = text(raw).slice(0, 120);
      if (task.length === 0 || seen.has(task.toLowerCase())) continue;
      seen.add(task.toLowerCase());
      tasks.push(task);
      if (tasks.length >= MAX_TASKS_PER_MILESTONE) break;
    }
    if (tasks.length === 0) continue;

    kept.push({
      // Numbered from what survived rather than from the model's own label:
      // dropping a task-less week 3 shouldn't leave a plan that reads 1, 2, 4.
      weekLabel: `Week ${kept.length + 1}`,
      title,
      tasks,
    });
  }

  return kept;
}

function text(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}
