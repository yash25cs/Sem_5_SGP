# StudyTrail privacy policy

StudyTrail is an exam-preparation app for university students. This page says
what it stores, who can see it, and how to delete it. It describes the app as
built in this repository.

## What StudyTrail stores

All of it lives in the project's Supabase database and private file storage,
protected so that each student can read only their own rows unless a section
below says otherwise.

- **Account** — your email address, a password (stored hashed by Supabase Auth;
  the app never sees it), your name, and the academic profile you enter:
  college, program and semester, and enrollment ID.
- **Study material** — the PDFs, notes and photos you upload, and the text read
  from them.
- **Study activity** — goals, subjects and exam dates, your roadmap and daily
  tasks, quiz attempts and answers, flashcards and their review schedule, focus
  sessions, XP, streaks, badges and rewards, and your time zone's offset from
  UTC so that streaks follow your own day.
- **Chat** — the questions you ask the AI tutor and its answers.
- **Exam practice** — past papers you upload and the questions read from them,
  and written answers with the marks and feedback they received. A photo of a
  handwritten answer is used only to read the answer and is deleted as soon as
  it has been marked; what was read from it is kept with the grade.
- **Study rooms** — messages you send, your group-quiz answers and scores, and
  any blocks or reports you make.
- **Doubt board** — doubts you post and answers you write.
- **Preferences** — the language you want explanations in.

## Who else can see it

- **Classmates**, once you join a class: your name, level, total XP and border
  on the class leaderboard; your doubts and answers on the class doubt board.
- **People in the same study room**: your name, whether you're focusing or on a
  break, the room's chat, and — once a group quiz ends — every player's score.
- **Anyone signed in**: an open study room's name, invite code and member count.
- Reports you file are kept for whoever runs the project to review.

## Services that process it

- **Supabase** hosts the database, file storage and server functions.
- **Google Gemini** receives the text of your material, your chat questions,
  doubts, and answers to be marked — including answer photos — only from the
  server, only to answer a request you made.

There is no advertising, no analytics SDK, no crash reporter and no device
identifier. Reminders and the home-screen widget are prepared on your phone.

## Deleting your data

In the app: **Settings → Delete account**. This removes your uploaded files,
then your account; every record of yours is deleted with it. See
[how to delete your account](delete-account.md) if you no longer have the app.

## Contact

yash@charusat.edu.in
