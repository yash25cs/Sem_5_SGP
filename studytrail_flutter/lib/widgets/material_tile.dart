// Flutter has its own `MaterialType` (for the `Material` widget); hiding it lets
// the app's material-source enum keep the unprefixed name here.
import 'package:flutter/material.dart' hide MaterialType;
import 'package:material_symbols_icons/symbols.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// One uploaded source, with its ingest status, a retry for the failed ones, and
/// a remove action.
///
/// Shared rather than private to a screen: the same row appears in onboarding's
/// upload step and in the chat screen's materials sheet, and the status chip is
/// the one place a student can tell a searchable file from a stuck one.
class MaterialTile extends StatelessWidget {
  const MaterialTile({
    super.key,
    required this.material,
    this.onRetry,
    this.onRemove,
    this.onSummarize,
  });

  final StudyMaterial material;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;

  /// Called when the student taps the Summarize button. Only visible for
  /// embedded materials — there's nothing to summarize until the chunks exist.
  final VoidCallback? onSummarize;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final isLink = material.sourceType == MaterialType.videoLink;
    // A YouTube video has its transcript stored behind it; a bare link is a
    // bookmark the AI never reads.
    final isVideo = isLink && material.storagePath != null;

    final (statusColor, statusTone) = switch (material.status) {
      IngestStatus.embedded => (p.green, ChipTone.green),
      IngestStatus.failed => (p.error, ChipTone.error),
      IngestStatus.processing => (p.amber, ChipTone.amber),
      IngestStatus.uploaded => (p.ink3, ChipTone.neutral),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            IconTile(
                isVideo
                    ? Symbols.smart_display
                    : isLink
                        ? Symbols.link
                        : Symbols.description,
                bg: statusColor.withValues(alpha: 0.14),
                fg: statusColor,
                size: 40,
                radius: 12),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(material.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  SoftChip(material.status.label, tone: statusTone, small: true),
                ],
              ),
            ),
            // Summarize only when embedded — there's nothing to read otherwise.
            if (material.status == IngestStatus.embedded &&
                onSummarize != null)
              RoundIconButton(Symbols.summarize, onTap: onSummarize),
            // Retry only on `failed`: nothing else is stuck. A bookmark link
            // never leaves `uploaded`, so it correctly gets no retry either.
            if (material.status == IngestStatus.failed)
              RoundIconButton(Symbols.refresh, onTap: onRetry),
            RoundIconButton(Symbols.close, onTap: onRemove),
          ],
        ),
      ),
    );
  }
}

