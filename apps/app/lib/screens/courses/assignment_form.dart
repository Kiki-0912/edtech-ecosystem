import 'package:edtech_app/models/assignment.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Labels for the assignment statuses the API accepts.
const kAssignmentStatuses = <String, String>{
  'draft': 'Draft',
  'open': 'Open',
  'closed': 'Closed',
};

/// Opens the create (no [initial]) or edit form for an assignment of
/// [courseId]. Resolves to the saved assignment, or null when cancelled.
Future<Assignment?> showAssignmentForm(
  BuildContext context, {
  required String courseId,
  Assignment? initial,
}) {
  return showFormSheet<Assignment>(
    context,
    title: initial == null ? 'New assignment' : 'Edit assignment',
    builder: (_) => AssignmentForm(courseId: courseId, initial: initial),
  );
}

/// Title, instructions, due date/time and status. Saves through
/// [ApiService] itself so API errors stay visible inside the sheet, then pops
/// with the saved [Assignment].
class AssignmentForm extends StatefulWidget {
  const AssignmentForm({super.key, required this.courseId, this.initial});

  final String courseId;
  final Assignment? initial;

  @override
  State<AssignmentForm> createState() => _AssignmentFormState();
}

class _AssignmentFormState extends State<AssignmentForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _brief;
  late DateTime _date;
  late TimeOfDay _time;
  late String _status;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _title = TextEditingController(text: a?.title ?? '');
    _brief = TextEditingController(text: a?.brief ?? '');
    // New assignments default to a week from today at 17:00.
    final due = a?.dueAt ??
        () {
          final now = DateTime.now();
          return DateTime(now.year, now.month, now.day + 7, 17);
        }();
    _date = DateTime(due.year, due.month, due.day);
    _time = TimeOfDay.fromDateTime(due);
    _status = kAssignmentStatuses.containsKey(a?.status) ? a!.status : 'open';
  }

  @override
  void dispose() {
    _title.dispose();
    _brief.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final dueAt =
        DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ApiService.instance;
    try {
      final initial = widget.initial;
      final saved = initial == null
          ? await api.createAssignment(
              courseId: widget.courseId,
              title: _title.text.trim(),
              brief: _brief.text.trim(),
              dueAt: dueAt,
              status: _status,
            )
          : await api.updateAssignment(
              initial.id,
              title: _title.text.trim(),
              brief: _brief.text.trim(),
              dueAt: dueAt,
              status: _status,
            );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            FormErrorBanner(message: _error!),
            const SizedBox(height: AppSpacing.md),
          ],
          TextFormField(
            key: const Key('assignment-title'),
            controller: _title,
            autofocus: widget.initial == null,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (v) {
              final text = v?.trim() ?? '';
              if (text.isEmpty) return 'Give the assignment a title';
              return text.length > 200
                  ? 'Keep the title under 200 characters'
                  : null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('assignment-brief'),
            controller: _brief,
            keyboardType: TextInputType.multiline,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Instructions',
              alignLabelWithHint: true,
            ),
            validator: (v) => (v?.trim().length ?? 0) > 10000
                ? 'Keep the instructions under 10,000 characters'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: DatePickerField(
                  key: const Key('assignment-due-date'),
                  label: 'Due date',
                  value: _date,
                  onChanged: (d) => setState(() => _date = d),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TimePickerField(
                  key: const Key('assignment-due-time'),
                  label: 'Due time',
                  value: _time,
                  onChanged: (t) => setState(() => _time = t),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            key: const Key('assignment-status'),
            initialValue: _status,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Status',
              helperText: 'Drafts are hidden from students',
            ),
            items: [
              for (final s in kAssignmentStatuses.entries)
                DropdownMenuItem(value: s.key, child: Text(s.value)),
            ],
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: BusyButton(
              key: const Key('assignment-save'),
              label: widget.initial == null ? 'Create assignment' : 'Save',
              busy: _busy,
              onPressed: _busy ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
