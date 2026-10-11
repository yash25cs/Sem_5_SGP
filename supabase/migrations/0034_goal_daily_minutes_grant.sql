-- ============================================================
-- 0034  Let the app save a custom pace.
--
--  0029 added goals.daily_minutes (the "Custom" pace) but 0008's column
--  grant on goals — name, exam_date, pace, is_active — was never widened,
--  so every write of it was "permission denied for table goals": creating a
--  goal with a custom pace failed, and so did any pace change in Settings,
--  since a preset pace clears daily_minutes in the same update. Found by
--  the live end-to-end test. The column carries no XP; its check
--  constraint (15–720) still holds.
--
-- Idempotent, like every migration here.
-- ============================================================

grant update (daily_minutes) on goals to authenticated;

notify pgrst, 'reload schema';
