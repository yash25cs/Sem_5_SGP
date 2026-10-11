import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';

/// How long the Undo bar stays after a task is ticked.
const taskUndoWindow = Duration(seconds: 5);

/// A task was just ticked: "Done" with Undo for a few seconds. After that the
/// tick stays; reopening it is a long-press (see [confirmReopenTask]), so a
/// stray tap can no longer undo real progress.
///
/// Shown the moment the tick lands on screen, not after the server answers;
/// returns the bar so the caller can take it down if the save fails.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showTaskDoneSnack(
  BuildContext context, {
  required String title,
  required VoidCallback onUndo,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  return messenger.showSnackBar(SnackBar(
    duration: taskUndoWindow,
    // A snackbar with an action stays up until tapped unless told otherwise
    // (`persist` defaults to true with an action), which left Undo stuck at
    // the bottom of the screen.
    persist: false,
    content: Text('Done: $title', maxLines: 1, overflow: TextOverflow.ellipsis),
    action: SnackBarAction(label: 'Undo', onPressed: onUndo),
  ));
}

/// Tapping a task that's already done: says how to reopen it.
void showTaskAlreadyDoneHint(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(const SnackBar(
    duration: Duration(seconds: 2),
    content: Text('Already done. Long-press it to mark it as not done.'),
  ));
}

/// Long-press on a done task. True only when the student confirms.
Future<bool> confirmReopenTask(BuildContext context, String title) async {
  final p = context.p;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Icon(Symbols.undo, color: p.primary, size: 30),
      title: Text('Mark as not done?',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
      content: Text(
          '“$title” goes back on your list. XP you earned for it stays, and '
          'ticking it again earns nothing more.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.ink2, fontSize: 14, height: 1.45)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('Cancel', style: TextStyle(color: p.ink3)),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('Mark as not done',
              style:
                  TextStyle(color: p.primary, fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return ok == true;
}
