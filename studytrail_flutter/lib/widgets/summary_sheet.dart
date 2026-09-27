import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../data/repositories/material_repository.dart';
import '../data/supabase_client.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Shows a loading state while the `summarize-material` Edge Function runs,
/// then renders the bullet-point summary in a scrollable bottom sheet.
///
/// Usage:
/// ```dart
/// SummarySheet.show(context, materialId: mat.id, title: mat.displayName);
/// ```
class SummarySheet extends StatefulWidget {
  const SummarySheet._({required this.materialId, required this.title});

  final String materialId;
  final String title;

  /// Opens the sheet as a modal bottom sheet.
  static void show(
    BuildContext context, {
    required String materialId,
    required String title,
  }) {
    final p = context.p;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) =>
          SummarySheet._(materialId: materialId, title: title),
    );
  }

  @override
  State<SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends State<SummarySheet> {
  String? _summary;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary =
          await const MaterialRepository().requestSummary(widget.materialId);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: p.line2,
                    borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 16),
            // Title
            Row(
              children: [
                Icon(Symbols.summarize, color: p.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Summary',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink3, fontSize: 13)),
            const SizedBox(height: 16),
            // Content
            Expanded(
              child: _loading
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: p.primary),
                          const SizedBox(height: 16),
                          Text('Summarizing…',
                              style: TextStyle(
                                  color: p.ink3,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text('Reading your material and extracting key points',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: p.ink3, fontSize: 12.5)),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Symbols.error,
                                  color: p.error, size: 36),
                              const SizedBox(height: 12),
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: p.ink2,
                                      fontSize: 14,
                                      height: 1.45)),
                              const SizedBox(height: 16),
                              PillButton('Try again', onTap: _fetch),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          controller: scrollController,
                          child: SelectableText(
                            _summary ?? '',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 14.5,
                                height: 1.65),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
