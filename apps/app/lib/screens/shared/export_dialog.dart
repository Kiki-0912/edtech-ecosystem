import 'package:edtech_app/services/csv.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Loads an export (`{headers, rows}` from the Excel endpoints), previews it
/// as CSV and copies it to the clipboard for pasting into a spreadsheet.
Future<void> showCsvExport(
  BuildContext context, {
  required String title,
  required Future<Map<String, dynamic>> Function() load,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ExportDialog(title: title, load: load),
  );
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.title, required this.load});

  final String title;
  final Future<Map<String, dynamic>> Function() load;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  String? _csv;
  int _rows = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _error = null);
    try {
      final data = await widget.load();
      final headers = List<String>.from(data['headers'] as List? ?? const []);
      final rows = (data['rows'] as List? ?? const [])
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _csv = toCsv(headers, rows);
        _rows = rows.length;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _csv ?? ''));
    if (!mounted) return;
    Navigator.of(context).pop();
    showToast(
      context,
      'Copied $_rows rows — paste into Excel or Sheets',
      kind: ToastKind.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: _error != null
            ? ErrorState(message: friendlyError(_error!), onRetry: _run)
            : _csv == null
                ? const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('$_rows rows · CSV',
                          style: context.text.labelMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 240),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: c.surfaceMuted,
                          borderRadius: AppRadius.mdAll,
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            _csv!,
                            key: const Key('export-preview'),
                            style: context.text.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          key: const Key('export-copy'),
          onPressed: _csv == null ? null : _copy,
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy CSV'),
        ),
      ],
    );
  }
}
