import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_theme.dart';
import 'common.dart';

/// Placeholder block shown while a screen's first fetch is in flight. Sized
/// like the content it replaces so the layout doesn't jump when data lands.
class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: p.card2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(color: p.ink3, strokeWidth: 2.4),
        ),
      ),
    );
  }
}

/// "Nothing here yet" state with an optional call to action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AppCard(
      child: Column(
        children: [
          IconTile(icon, bg: p.primarySoft, fg: p.primary, size: 54),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.ink3, fontSize: 13, height: 1.5),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            PillButton(actionLabel!, onTap: onAction),
          ],
        ],
      ),
    );
  }
}

/// Whole-screen failure with a retry — the [ErrorNotice] of a screen that has
/// no content to show around it.
///
/// Used when the app can't start: there is no shell, no tab bar, and nothing
/// cached to fall back on, so a spinner would spin forever and an inline notice
/// would have nothing to sit inside.
class ErrorScreen extends StatelessWidget {
  const ErrorScreen({
    super.key,
    required this.message,
    this.offline = false,
    this.onRetry,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String message;

  /// Changes the wording and icon only. Being offline is the student's problem
  /// to fix and says so; anything else is ours and shouldn't blame their Wi-Fi.
  final bool offline;

  final VoidCallback? onRetry;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTile(offline ? Symbols.wifi_off : Symbols.error,
                    bg: offline ? p.amberSoft : p.errorSoft,
                    fg: offline ? p.amber : p.error,
                    size: 68,
                    radius: 22),
                const SizedBox(height: 20),
                Text(offline ? "You're offline" : 'Something went wrong',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4)),
                const SizedBox(height: 10),
                Text(message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.ink2, fontSize: 14, height: 1.55)),
                const SizedBox(height: 26),
                if (onRetry != null)
                  PillButton('Try again',
                      icon: Symbols.refresh, onTap: onRetry),
                if (secondaryLabel != null && onSecondary != null) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onSecondary,
                    child: Text(secondaryLabel!,
                        style: TextStyle(
                            color: p.ink3, fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Failure state with a retry. Shows the friendly message the repository layer
/// produced, never a raw exception.
class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: p.errorSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.error.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.error, color: p.error, size: 22, fill: 1),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: p.onError, fontSize: 13, height: 1.45),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text('Retry',
                  style: TextStyle(
                      color: p.error, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}
