import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Department admin: create, rename and delete departments and manage which
/// students belong to each. Assignment is tap-based (works on touch and with
/// assistive tech), replacing the old drag-and-drop board.
class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  List<Map<String, dynamic>> _departments = const [];
  List<Map<String, dynamic>> _students = const [];
  Map<String, List<Map<String, dynamic>>> _members = const {};
  String _query = '';
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ApiService.instance;
    setState(() {
      _loading = _departments.isEmpty;
      _error = null;
    });
    try {
      final results =
          await Future.wait([api.getDepartments(), api.getStudents()]);
      final departments = results[0];
      final memberLists = await Future.wait(departments.map((d) => api
          .getStudentsByDepartment(d['id'].toString())
          .catchError((_) => <Map<String, dynamic>>[])));
      if (!mounted) return;
      setState(() {
        _departments = departments;
        _students = results[1];
        _members = {
          for (var i = 0; i < departments.length; i++)
            departments[i]['id'].toString(): memberLists[i],
        };
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

  int get _unassigned {
    final assigned = {
      for (final list in _members.values)
        for (final s in list) s['id'].toString(),
    };
    return _students
        .where((s) => !assigned.contains(s['id'].toString()))
        .length;
  }

  Future<void> _openForm([Map<String, dynamic>? department]) async {
    final saved = await showFormSheet<bool>(
      context,
      title: department == null ? 'New department' : 'Edit department',
      builder: (_) => _DepartmentForm(department: department),
    );
    if (saved == true) {
      if (mounted) {
        showToast(context,
            department == null ? 'Department created' : 'Department updated',
            kind: ToastKind.success);
      }
      await _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final count = _members[d['id'].toString()]?.length ?? 0;
    final ok = await confirmDialog(
      context,
      title: 'Delete ${d['name']}?',
      message: count == 0
          ? 'This department has no students.'
          : '$count students will be unassigned from this department.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ApiService.instance.deleteDepartment(d['id'].toString());
      if (mounted) {
        showToast(context, 'Department deleted', kind: ToastKind.success);
      }
      await _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), kind: ToastKind.error);
    }
  }

  Future<void> _openMembers(Map<String, dynamic> d) async {
    await showFormSheet<void>(
      context,
      title: d['name']?.toString() ?? 'Department',
      builder: (_) => _MembersPanel(department: d, allStudents: _students),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = _departments
        .where((d) =>
            q.isEmpty ||
            (d['name']?.toString().toLowerCase() ?? '').contains(q) ||
            (d['code']?.toString().toLowerCase() ?? '').contains(q))
        .toList();

    return AppPage(
      title: 'Departments',
      subtitle: 'Programmes and the students enrolled in them',
      onRefresh: _load,
      actions: [
        FilledButton.icon(
          key: const Key('department-add'),
          onPressed: () => _openForm(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('New department'),
        ),
      ],
      children: [
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          isEmpty: false,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ResponsiveGrid(
                minItemWidth: 160,
                children: [
                  StatTile(
                      label: 'Departments',
                      value: '${_departments.length}',
                      icon: Icons.account_tree_outlined,
                      tone: Tone.info),
                  StatTile(
                      label: 'Students',
                      value: '${_students.length}',
                      icon: Icons.groups_outlined),
                  StatTile(
                      label: 'Unassigned',
                      value: '$_unassigned',
                      icon: Icons.person_off_outlined,
                      tone: _unassigned == 0 ? Tone.success : Tone.warning),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SearchField(
                hint: 'Search departments',
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: AppSpacing.md),
              if (shown.isEmpty)
                const EmptyState(
                    icon: Icons.account_tree_outlined, title: 'No departments')
              else
                ResponsiveGrid(
                  minItemWidth: 300,
                  children: [
                    for (final d in shown)
                      _DepartmentCard(
                        department: d,
                        members: _members[d['id'].toString()] ?? const [],
                        onOpen: () => _openMembers(d),
                        onEdit: () => _openForm(d),
                        onDelete: () => _delete(d),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  const _DepartmentCard({
    required this.department,
    required this.members,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> department;
  final List<Map<String, dynamic>> members;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final id = department['id'].toString();
    return AppCard(
      key: Key('department-$id'),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(
                  label: department['code']?.toString() ?? '',
                  tone: Tone.accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(department['category']?.toString() ?? '',
                    style: context.text.bodySmall),
              ),
              PopupMenuButton<String>(
                key: Key('department-menu-$id'),
                tooltip: 'Actions',
                onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          Text(department['name']?.toString() ?? '',
              style: context.text.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final m in members.take(4))
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xxs),
                  child: Avatar(
                      name: m['displayName']?.toString() ?? '?', size: 28),
                ),
              if (members.isNotEmpty) const SizedBox(width: AppSpacing.xxs),
              Text(
                members.isEmpty
                    ? 'No students yet'
                    : '${members.length} ${members.length == 1 ? 'student' : 'students'}',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _categories = <String, int>{
  '3 Years': 36,
  '2 Years': 24,
  '6 Months': 6,
  '2 Years Paramedical': 24,
};

class _DepartmentForm extends StatefulWidget {
  const _DepartmentForm({required this.department});

  final Map<String, dynamic>? department;

  @override
  State<_DepartmentForm> createState() => _DepartmentFormState();
}

class _DepartmentFormState extends State<_DepartmentForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late String _category;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final d = widget.department;
    _name = TextEditingController(text: d?['name']?.toString() ?? '');
    _code = TextEditingController(text: d?['code']?.toString() ?? '');
    final cat = d?['category']?.toString();
    _category = _categories.containsKey(cat) ? cat! : '3 Years';
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final api = ApiService.instance;
    try {
      if (widget.department == null) {
        await api.createDepartment(
          name: _name.text.trim(),
          code: _code.text.trim().toUpperCase(),
          category: _category,
          durationMonths: _categories[_category]!,
        );
      } else {
        await api.updateDepartment(
          id: widget.department!['id'].toString(),
          name: _name.text.trim(),
          code: _code.text.trim().toUpperCase(),
          category: _category,
          durationMonths: _categories[_category]!,
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
            key: const Key('department-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('department-code'),
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration:
                const InputDecoration(labelText: 'Code', hintText: 'e.g. CIT'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a short code' : null,
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Programme length'),
            items: [
              for (final c in _categories.keys)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: BusyButton(
              key: const Key('department-save'),
              label: widget.department == null ? 'Create department' : 'Save',
              busy: _busy,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}

/// Members of one department with add/remove.
class _MembersPanel extends StatefulWidget {
  const _MembersPanel({required this.department, required this.allStudents});

  final Map<String, dynamic> department;
  final List<Map<String, dynamic>> allStudents;

  @override
  State<_MembersPanel> createState() => _MembersPanelState();
}

class _MembersPanelState extends State<_MembersPanel> {
  List<Map<String, dynamic>> _members = const [];
  bool _loading = true;
  String? _busyId;

  String get _deptId => widget.department['id'].toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await ApiService.instance.getStudentsByDepartment(_deptId);
      if (mounted) {
        setState(() {
          _members = m;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showToast(context, friendlyError(e), kind: ToastKind.error);
      }
    }
  }

  Future<void> _toggle(Map<String, dynamic> student, bool add) async {
    final id = student['id'].toString();
    setState(() => _busyId = id);
    try {
      final api = ApiService.instance;
      if (add) {
        await api.enrollStudentInDepartment(
            studentId: id, departmentId: _deptId);
      } else {
        await api.unenrollStudentFromDepartment(
            studentId: id, departmentId: _deptId);
      }
      await _load();
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SkeletonList(count: 3, itemHeight: 48);
    final memberIds = _members.map((m) => m['id'].toString()).toSet();
    final others = widget.allStudents
        .where((s) => !memberIds.contains(s['id'].toString()))
        .toList();

    Widget row(Map<String, dynamic> s, bool member) {
      final id = s['id'].toString();
      return ListRow(
        dense: true,
        leading: Avatar(name: s['displayName']?.toString() ?? '?', size: 32),
        title: s['displayName']?.toString() ?? 'Student',
        subtitle: s['rollNumber']?.toString(),
        trailing: _busyId == id
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : member
                ? IconButton(
                    key: Key('member-remove-$id'),
                    tooltip: 'Remove from department',
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed: () => _toggle(s, false),
                  )
                : IconButton(
                    key: Key('member-add-$id'),
                    tooltip: 'Add to department',
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: () => _toggle(s, true),
                  ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('MEMBERS · ${_members.length}', style: context.text.labelSmall),
        const SizedBox(height: AppSpacing.xs),
        if (_members.isEmpty)
          Text('No students yet.', style: context.text.bodyMedium)
        else
          for (final s in _members) row(s, true),
        const SizedBox(height: AppSpacing.md),
        Text('ADD STUDENTS', style: context.text.labelSmall),
        const SizedBox(height: AppSpacing.xs),
        if (others.isEmpty)
          Text('Every student is already a member.',
              style: context.text.bodyMedium)
        else
          for (final s in others) row(s, false),
      ],
    );
  }
}
