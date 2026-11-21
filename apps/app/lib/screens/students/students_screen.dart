import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/screens/home/home_data.dart' show myCourses;
import 'package:edtech_app/screens/shared/export_dialog.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/services/csv.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Student roster. Admins add, edit, delete and import; teachers get a
/// read-only view of the students in their courses and can export.
class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  List<Map<String, dynamic>> _students = const [];
  List<Course> _courses = const [];
  String _query = '';
  String? _courseFilter;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final api = ApiService.instance;
    setState(() {
      _loading = _students.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([api.getStudents(), api.getCourses()]);
      final courses = myCourses(user, results[1] as List<Course>);
      var students = results[0] as List<Map<String, dynamic>>;
      if (!user.isAdmin) {
        final ids = courses.map((c) => c.id).toSet();
        students =
            students.where((s) => _courseIds(s).any(ids.contains)).toList();
      }
      students.sort((a, b) => _name(a).compareTo(_name(b)));
      if (!mounted) return;
      setState(() {
        _students = students;
        _courses = courses;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  static String _name(Map<String, dynamic> s) =>
      s['displayName']?.toString() ?? '';

  static List<String> _courseIds(Map<String, dynamic> s) => List<String>.from(
      (s['courseIds'] as List?)?.map((e) => e.toString()) ?? const <String>[]);

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    return _students.where((s) {
      if (_courseFilter != null && !_courseIds(s).contains(_courseFilter)) {
        return false;
      }
      if (q.isEmpty) return true;
      return [s['displayName'], s['email'], s['phone'], s['rollNumber']]
          .any((v) => (v?.toString().toLowerCase() ?? '').contains(q));
    }).toList();
  }

  String _coursesLabel(Map<String, dynamic> s) {
    final codes = _courseIds(s)
        .map((id) => _courses.where((c) => c.id == id).firstOrNull?.code)
        .whereType<String>()
        .toList();
    return codes.isEmpty ? 'No courses' : codes.join(', ');
  }

  Future<void> _openForm([Map<String, dynamic>? student]) async {
    final saved = await showFormSheet<bool>(
      context,
      title: student == null ? 'Add student' : 'Edit student',
      builder: (_) => _StudentForm(student: student, courses: _courses),
    );
    if (saved == true) {
      if (mounted) {
        showToast(
            context, student == null ? 'Student added' : 'Student updated',
            kind: ToastKind.success);
      }
      await _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> student) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove student?',
      message:
          '${_name(student)} will be removed from the roster and all courses.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ApiService.instance.deleteStudent(student['id'].toString());
      if (mounted) {
        showToast(context, 'Student removed', kind: ToastKind.success);
      }
      await _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), kind: ToastKind.error);
    }
  }

  Future<void> _import() async {
    final result = await showFormSheet<Map<String, dynamic>>(
      context,
      title: 'Import students',
      builder: (_) => _ImportForm(courses: _courses),
    );
    if (result == null || !mounted) return;
    final imported = result['imported'] ?? 0;
    final errors = (result['errors'] as List?)?.length ?? 0;
    showToast(
      context,
      errors == 0
          ? 'Imported $imported students'
          : 'Imported $imported students · $errors rows skipped',
      kind: errors == 0 ? ToastKind.success : ToastKind.info,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AuthProvider>().user?.isAdmin ?? false;
    final filtered = _filtered;
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return AppPage(
      title: 'Students',
      subtitle: admin
          ? '${_students.length} students enrolled'
          : 'Students in your courses',
      onRefresh: _load,
      actions: [
        OutlinedButton.icon(
          key: const Key('students-export'),
          onPressed: () => showCsvExport(
            context,
            title: 'Export students',
            load: () => ApiService.instance
                .exportStudentsToExcel(courseId: _courseFilter),
          ),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Export'),
        ),
        if (admin) ...[
          OutlinedButton.icon(
            key: const Key('students-import'),
            onPressed: _import,
            icon: const Icon(Icons.upload_rounded, size: 18),
            label: const Text('Import'),
          ),
          FilledButton.icon(
            key: const Key('student-add'),
            onPressed: () => _openForm(),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Add student'),
          ),
        ],
      ],
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchField(
              key: const Key('students-search'),
              hint: 'Search name, email, phone or roll number',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_courses.isNotEmpty)
              FilterChips<String?>(
                options: [
                  const FilterOption(null, 'All courses'),
                  for (final c in _courses) FilterOption(c.id, c.code),
                ],
                selected: _courseFilter,
                onSelected: (v) => setState(() => _courseFilter = v),
              ),
          ],
        ),
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          isEmpty: filtered.isEmpty,
          empty: EmptyState(
            icon: Icons.groups_outlined,
            title: _students.isEmpty ? 'No students yet' : 'No matches',
            message: _students.isEmpty && admin
                ? 'Add students one by one or import a spreadsheet.'
                : null,
          ),
          builder: (_) => AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                if (wide) const _TableHeader(),
                for (var i = 0; i < filtered.length; i++) ...[
                  if (i > 0) const Divider(),
                  _StudentRow(
                    student: filtered[i],
                    courses: _coursesLabel(filtered[i]),
                    wide: wide,
                    onEdit: admin ? () => _openForm(filtered[i]) : null,
                    onDelete: admin ? () => _delete(filtered[i]) : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final style = context.text.labelSmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('NAME', style: style)),
          Expanded(flex: 2, child: Text('ROLL NO.', style: style)),
          Expanded(flex: 3, child: Text('CONTACT', style: style)),
          Expanded(flex: 2, child: Text('COURSES', style: style)),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.student,
    required this.courses,
    required this.wide,
    this.onEdit,
    this.onDelete,
  });

  final Map<String, dynamic> student;
  final String courses;
  final bool wide;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final name = student['displayName']?.toString() ?? 'Student';
    final roll = student['rollNumber']?.toString() ?? '—';
    final phone = student['phone']?.toString() ?? '';
    final email = student['email']?.toString() ?? '';
    final id = student['id'].toString();

    final menu = onEdit == null
        ? const SizedBox(width: 48)
        : PopupMenuButton<String>(
            key: Key('student-menu-$id'),
            tooltip: 'Actions',
            onSelected: (v) => v == 'edit' ? onEdit!() : onDelete!(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Remove')),
            ],
          );

    if (!wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: ListRow(
          leading: Avatar(name: name),
          title: name,
          subtitle:
              [roll, phone, courses].where((s) => s.isNotEmpty).join(' · '),
          trailing: menu,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Avatar(name: name, size: 32),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(name,
                      style: context.text.titleSmall,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Expanded(flex: 2, child: Text(roll, style: context.text.bodyMedium)),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(phone, style: context.text.bodyMedium),
                if (email.isNotEmpty)
                  Text(email,
                      style: context.text.bodySmall,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Expanded(
              flex: 2,
              child: Text(courses,
                  style: context.text.bodyMedium,
                  overflow: TextOverflow.ellipsis)),
          menu,
        ],
      ),
    );
  }
}

class _StudentForm extends StatefulWidget {
  const _StudentForm({required this.student, required this.courses});

  final Map<String, dynamic>? student;
  final List<Course> courses;

  @override
  State<_StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends State<_StudentForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  String? _courseId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = widget.student;
    _name = TextEditingController(text: s?['displayName']?.toString() ?? '');
    _email = TextEditingController(text: s?['email']?.toString() ?? '');
    _phone = TextEditingController(text: s?['phone']?.toString() ?? '');
    final ids =
        (s?['courseIds'] as List?)?.map((e) => e.toString()) ?? const [];
    _courseId =
        ids.where((id) => widget.courses.any((c) => c.id == id)).firstOrNull;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final api = ApiService.instance;
    try {
      if (widget.student == null) {
        await api.createStudent(
          displayName: _name.text.trim(),
          email: _email.text.trim(),
          phone: _phone.text.trim(),
          courseId: _courseId,
        );
      } else {
        await api.updateStudent(
          studentId: widget.student!['id'].toString(),
          displayName: _name.text.trim(),
          email: _email.text.trim(),
          phone: _phone.text.trim(),
          courseId: _courseId,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, friendlyError(e), kind: ToastKind.error);
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
          TextFormField(
            key: const Key('student-name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('student-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) => (v != null && v.isNotEmpty && !v.contains('@'))
                ? 'Enter a valid email'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('student-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a phone number' : null,
          ),
          if (widget.courses.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String?>(
              key: const Key('student-course'),
              initialValue: _courseId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Course'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('None')),
                for (final c in widget.courses)
                  DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text('${c.code} · ${c.title}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _courseId = v),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: BusyButton(
              key: const Key('student-save'),
              label: widget.student == null ? 'Add student' : 'Save changes',
              busy: _busy,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportForm extends StatefulWidget {
  const _ImportForm({required this.courses});

  final List<Course> courses;

  @override
  State<_ImportForm> createState() => _ImportFormState();
}

class _ImportFormState extends State<_ImportForm> {
  final _csv = TextEditingController();
  String? _courseId;
  List<Map<String, String>> _rows = const [];
  bool _busy = false;

  static const _aliases = {
    'name': 'name',
    'fullname': 'name',
    'rollnumber': 'rollNumber',
    'rollno': 'rollNumber',
    'roll': 'rollNumber',
    'contact': 'contact',
    'phone': 'contact',
    'departmentid': 'departmentId',
  };

  @override
  void initState() {
    super.initState();
    _courseId = widget.courses.firstOrNull?.id;
    _csv.addListener(() =>
        setState(() => _rows = parseCsvRecords(_csv.text, aliases: _aliases)));
  }

  @override
  void dispose() {
    _csv.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rows.isEmpty || _courseId == null) return;
    setState(() => _busy = true);
    try {
      final result = await ApiService.instance.importStudentsFromExcel(
        courseId: _courseId!,
        rows: _rows,
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, friendlyError(e), kind: ToastKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _rows
        .where((r) =>
            (r['name'] ?? '').isNotEmpty &&
            (r['rollNumber'] ?? '').isNotEmpty &&
            (r['contact'] ?? '').isNotEmpty)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Paste rows from Excel or Google Sheets, or a CSV with the columns '
          'name, rollNumber, contact (departmentId optional).',
          style: context.text.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          key: const Key('import-course'),
          initialValue: _courseId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Enrol into course'),
          items: [
            for (final c in widget.courses)
              DropdownMenuItem(
                  value: c.id,
                  child: Text('${c.code} · ${c.title}',
                      overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _courseId = v),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const Key('import-csv'),
          controller: _csv,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(
            labelText: 'CSV',
            hintText:
                'name,rollNumber,contact\nAyesha Khan,CIT-2026-010,+923001234567',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _rows.isEmpty
              ? 'No rows yet'
              : '$valid of ${_rows.length} rows ready'
                  '${valid < _rows.length ? ' · rows missing name, roll number or contact will be skipped' : ''}',
          style: context.text.labelMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerRight,
          child: BusyButton(
            key: const Key('import-submit'),
            label: valid == 0 ? 'Import' : 'Import $valid students',
            busy: _busy,
            onPressed: valid == 0 || _courseId == null ? null : _submit,
          ),
        ),
      ],
    );
  }
}
