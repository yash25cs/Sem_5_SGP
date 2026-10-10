import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/nav.dart';

/// What StudyTrail stores, who can see it, and how to delete it — the
/// in-app version of `docs/privacy-policy.md`. Keep the two saying the same.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key, this.onBack});
  final VoidCallback? onBack;

  static const _sections = <(IconData, String, List<String>)>[
    (
      Symbols.database,
      'What StudyTrail stores',
      [
        'Your account: email, name, and the academic profile you enter. Your '
            'password is stored hashed by Supabase; the app never sees it.',
        'Your study material: the PDFs, notes, photos and videos you add, and '
            'the text read from them.',
        'Your study activity: goals, subjects, exam dates, roadmap, tasks, '
            'quizzes, flashcards, focus sessions, XP, streaks, badges and '
            'rewards.',
        'Chat questions and answers, past papers you upload, and written '
            'answers with their marks. A photo of a handwritten answer is '
            'deleted as soon as it has been marked.',
        'Doubts and answers you post, and messages in study rooms.',
      ],
    ),
    (
      Symbols.visibility,
      'Who else can see it',
      [
        'Every StudyTrail student: your name, level, total XP and border on '
            'the leaderboard, and the doubts and answers you post on the '
            'doubt board.',
        'People in the same study room: your name, whether you are focusing, '
            'the room chat, and group-quiz scores.',
        'Everything else — your notes, chats, quizzes, marks and plan — is '
            'private to your account, enforced by the database itself.',
      ],
    ),
    (
      Symbols.smart_toy,
      'Services that process it',
      [
        'Supabase hosts the database, file storage and server functions.',
        'Google Gemini receives the text it needs to answer a request you '
            'made — your notes, a chat question, an answer to mark — and only '
            'from the server.',
        'No ads, no analytics, no crash reporter, no device identifier.',
      ],
    ),
    (
      Symbols.phone_android,
      'On your phone',
      [
        'Reminders and home-screen widgets are prepared on the phone.',
        'Calendar access is asked for only when you turn on “Add to my '
            'calendar”. StudyTrail writes only its own events and removes '
            'them when you turn it off.',
        'The camera and photos are used only when you choose to photograph '
            'notes or an answer.',
      ],
    ),
    (
      Symbols.delete_forever,
      'Deleting your data',
      [
        'Settings → Delete account removes your uploaded files and then your '
            'account, and every record of yours goes with it.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        children: [
          const TopInset(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 20, 6),
            child: Row(
              children: [
                RoundIconButton(Symbols.arrow_back,
                    onTap: onBack ?? () => Navigator.of(context).maybePop()),
                const SizedBox(width: 8),
                Text('Privacy & security',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                for (final (icon, title, points) in _sections) ...[
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          IconTile(icon,
                              bg: p.primarySoft,
                              fg: p.primary,
                              size: 34,
                              radius: 11),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(title,
                                style: TextStyle(
                                    color: p.ink,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        for (final point in points)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 7),
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                        color: p.ink3, shape: BoxShape.circle),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(point,
                                      style: TextStyle(
                                          color: p.ink2,
                                          fontSize: 13.5,
                                          height: 1.45)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
