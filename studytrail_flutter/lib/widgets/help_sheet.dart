import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Short answers to what students ask most, from Settings and Profile.
Future<void> showHelpSheet(BuildContext context) {
  final p = context.p;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => const _HelpSheet(),
  );
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  static const _faq = <(String, String)>[
    (
      'How is my roadmap made?',
      'From your goal: each subject, its exam date, and the study time a day '
          'you chose. Add a syllabus to a subject on Home and the plan follows '
          'its units. Settings → Study goals lets you change any of it.',
    ),
    (
      'Where do quizzes and flashcards come from?',
      'From the notes you upload — PDFs, photos of pages, or YouTube videos '
          'with captions. The more you add, the better they get.',
    ),
    (
      'How is a written answer marked?',
      'Against your own notes, like an examiner would, in steps of half a '
          'mark. Theory and NEP case questions are both marked part by part '
          'where they have parts.',
    ),
    (
      'How do I earn XP?',
      'Tick off daily tasks, finish focus sessions, review flashcards that are '
          'due and answer quiz questions. The leaderboard ranks every student '
          'by XP ever earned.',
    ),
    (
      'Can I change when I\'m reminded?',
      'Yes — Settings → Daily study reminder. Tap the time to change it, or '
          'switch it off.',
    ),
    (
      'How do my exams get into my calendar?',
      'Turn on Settings → Add to my calendar. Exams, roadmap weeks and tasks '
          'are added to your phone\'s calendar and kept up to date.',
    ),
    (
      'How do I delete my account?',
      'Settings → Delete account. Your files and every record of yours are '
          'removed.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            Text('Help',
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final (q, a) in _faq)
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  title: Text(q,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(a,
                          style: TextStyle(
                              color: p.ink2, fontSize: 13.5, height: 1.45)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
