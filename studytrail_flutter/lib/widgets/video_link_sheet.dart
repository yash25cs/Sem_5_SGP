import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../services/youtube_service.dart';
import '../state/stores.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Asks for a link and adds it: a YouTube video or playlist is read in through
/// its captions, anything else is kept as a bookmark.
///
/// Shared by onboarding's upload step and the chat screen's materials sheet,
/// which is the only way to add material once onboarding is over. [toast] is
/// the caller's, because a playlist can take long enough that the student has
/// left the screen this started on.
Future<void> addVideoLink(
  BuildContext context, {
  required ValueChanged<String> toast,
}) async {
  final store = context.read<OnboardingStore>();
  final url = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => const _LinkSheet(),
  );
  if (url == null || url.isEmpty || !context.mounted) return;

  final link = YouTubeLink.parse(url);
  if (link == null) {
    // Not YouTube: an article or a course page. Nothing on the phone can read
    // an arbitrary page, so it's saved as a bookmark and says so.
    final ok = await store.addLink(url);
    toast(ok
        ? "Link saved — the AI can't read web pages, only YouTube videos"
        : store.error ?? 'Could not add that link');
    return;
  }
  if (!link.isUsable) {
    toast("That YouTube link isn't a video or a playlist.");
    return;
  }

  var wholePlaylist = true;
  if (link.videoId != null && link.playlistId != null) {
    final choice = await _askWholePlaylist(context);
    if (choice == null || !context.mounted) return;
    wholePlaylist = choice;
  }

  final result = await store.importYouTube(link, wholePlaylist: wholePlaylist);
  final summary = result?.summary;
  toast(summary ?? store.error ?? 'Could not add that video');
}

/// `watch?v=…&list=…` is a video opened from inside a playlist; which one was
/// meant can't be told from the link, so it's asked.
Future<bool?> _askWholePlaylist(BuildContext context) {
  final p = context.p;
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This video is part of a playlist',
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
                'Add every video in the playlist, or only the one you '
                'were watching?',
                style: TextStyle(color: p.ink2, fontSize: 13.5, height: 1.45)),
            const SizedBox(height: 18),
            PillButton('Whole playlist',
                icon: Symbols.playlist_play,
                onTap: () => Navigator.of(sheetContext).pop(true)),
            const SizedBox(height: 10),
            PillButton('Just this video',
                icon: Symbols.smart_display,
                variant: PillVariant.outline,
                onTap: () => Navigator.of(sheetContext).pop(false)),
          ],
        ),
      ),
    ),
  );
}

/// The paste-a-link sheet.
///
/// Stateful so that it owns its [TextEditingController]. The caller used to
/// create the controller and dispose it as soon as the sheet's future
/// completed — but that future completes when the sheet *starts* closing, while
/// the field is still on screen animating out. Disposing it there crashed
/// debug builds with `'_dependents.isEmpty': is not true`. Here it's disposed
/// with the field.
class _LinkSheet extends StatefulWidget {
  const _LinkSheet();

  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: p.line),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a YouTube video or playlist',
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
                'The AI reads the captions, so it can answer from the lecture '
                'and point you to the moment.',
                style: TextStyle(color: p.ink2, fontSize: 13, height: 1.45)),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              style: TextStyle(color: p.ink, fontSize: 14.5),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'https://youtube.com/playlist?list=…',
                hintStyle: TextStyle(color: p.ink3, fontSize: 14),
                filled: true,
                fillColor: p.card2,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: border,
                enabledBorder: border,
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: p.primary, width: 1.6),
                ),
              ),
            ),
            const SizedBox(height: 18),
            PillButton('Add link', icon: Symbols.link, onTap: _submit),
          ],
        ),
      ),
    );
  }
}
