import 'package:edtech_app/models/admin.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/screens/shared/export_dialog.dart';
import 'package:edtech_app/screens/students/students_screen.dart'
    show showStudentImport;
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Spreadsheet import and export in one place. Reuses the main app's student
/// import form and CSV export dialog.
class AdminImportExportScreen extends StatefulWidget {
  const AdminImportExportScreen({super.key});

  @override
  State<AdminImportExportScreen> createState() =>
      _AdminImportExportScreenState();
}

class _AdminImportExportScreenState extends State<AdminImportExportScreen> {
  List<Course> _courses = const [];
  String? _courseId;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _courses.isEmpty;
      _error = null;
    });
    try {
      final courses = await ApiService.instance.adminListCourses();
      if (!mounted) return;
      setState(() {
        _courses = [for (final c in courses) _asCourse(c)]
          ..sort((a, b) => a.code.compareTo(b.code));
        if (!_courses.any((c) => c.id == _courseId)) _courseId = null;
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

  static Course _asCourse(AdminCourse c) => Course(
        id: c.id,
        title: c.title,
        code: c.code,
        teacherId: c.teacherId,
        studentIds: c.studentIds,
        term: c.term,
        createdAt: c.createdAt,
        teacherName: c.teacherName,
      );

  Future<void> _import() async {
    final result = await showStudentImport(context, _courses);
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
    final api = ApiService.instance;
    return AppPage(
      title: 'Import/Export',
      subtitle: 'Move students, attendance and notes in and out as CSV',
      onRefresh: _load,
      children: [
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          isEmpty: false,
          builder: (_) => TwoPane(
            primaryFlex: 1,
            secondaryFlex: 1,
            primary: SectionCard(
              title: 'Import students',
              subtitle: 'Paste rows from Excel, Google Sheets or a CSV file',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _courses.isEmpty
                        ? 'Create a course first: imported students are '
                            'enrolled into one.'
                        : 'Columns: name, rollNumber, contact '
                            '(departmentId optional). Each student is '
                            'enrolled into the course you pick.',
                    style: context.text.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    key: const Key('import-export-import'),
                    onPressed: _courses.isEmpty ? null : _import,
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: const Text('Import students'),
                  ),
                ],
              ),
            ),
            secondary: SectionCard(
              title: 'Export',
              subtitle: 'Preview and copy as CSV',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String?>(
                    key: const Key('import-export-course'),
                    initialValue: _courseId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Course'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('All courses')),
                      for (final c in _courses)
                        DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text('${c.code} · ${c.title}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _courseId = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('import-export-students'),
                        onPressed: () => showCsvExport(
                          context,
                          title: 'Export students',
                          load: () =>
                              api.exportStudentsToExcel(courseId: _courseId),
                        ),
                        icon: const Icon(Icons.groups_outlined, size: 18),
                        label: const Text('Students'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('import-export-attendance'),
                        onPressed: () => showCsvExport(
                          context,
                          title: 'Export attendance',
                          load: () =>
                              api.exportAttendanceToExcel(courseId: _courseId),
                        ),
                        icon: const Icon(Icons.fact_check_outlined, size: 18),
                        label: const Text('Attendance'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('import-export-notes'),
                        onPressed: () => showCsvExport(
                          context,
                          title: 'Export notes',
                          load: () =>
                              api.exportNotesToExcel(courseId: _courseId),
                        ),
                        icon:
                            const Icon(Icons.sticky_note_2_outlined, size: 18),
                        label: const Text('Notes'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
