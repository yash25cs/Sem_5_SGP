-- ============================================================
-- 0036  Rename the old default class.
--
--  0006 seeded a default class named after the college the project was
--  first built at. Classes have been unused since 0029 (one community for
--  everyone) and nothing in the app shows them, but the row was still
--  there. It becomes a neutral "Default class", matching the edited 0006,
--  so re-running the migrations doesn't add a second one.
--
-- Idempotent, like every migration here.
-- ============================================================

update classes
   set name = 'Default class', college = null, branch = null, batch = null
 where name = 'CE-A 2025';
