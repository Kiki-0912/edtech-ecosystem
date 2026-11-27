import 'dart:async';

import 'package:edtech_app/admin/admin_access.dart';
import 'package:edtech_app/auth/auth_layout.dart' show PasswordField;
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/models/admin.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Minimum password length the admin API accepts.
const kMinAdminPasswordLength = 8;

/// Shown on the login screen after an admin resets their own password.
const kOwnPasswordChangedMessage =
    'Your password was changed. Sign in with the new password.';

const _roles = <FilterOption<String>>[
  FilterOption('student', 'Student'),
  FilterOption('teacher', 'Teacher'),
  FilterOption('admin', 'Admin'),
];

/// The Users page, filtered: `/users?role=student`, `/users?status=inactive`.
String adminUsersLocation({String? role, String? status}) => Uri(
      path: '/users',
      queryParameters: {
        if (role != null) 'role': role,
        if (status != null && status != 'all') 'status': status,
      },
    ).toString();

String roleName(String role) =>
    _roles.where((r) => r.value == role).firstOrNull?.label ?? role;

IconData roleIcon(String role) => switch (role) {
      'admin' => Icons.admin_panel_settings_outlined,
      'teacher' => Icons.co_present_outlined,
      _ => Icons.school_outlined,
    };

/// Every account: search, filter by role and status, create (any role),
/// edit, activate / deactivate, reset password and delete. Errors such as
/// LAST_ADMIN or USER_IN_USE come from the API and are shown as-is.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, this.initialRole, this.initialStatus});

  /// Starting filters, from `/users?role=student` or `/users?status=inactive`
  /// (the overview tiles link there). Unknown values are ignored.
  final String? initialRole;
  final String? initialStatus;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  List<AdminUser> _users = const [];
  String _query = '';
  String? _role;
  String _status = 'all';

  static String? _validRole(String? role) =>
      _roles.any((r) => r.value == role) ? role : null;

  static String _validStatus(String? status) =>
      const ['active', 'inactive'].contains(status) ? status! : 'all';
  bool _loading = true;
  bool _loaded = false;
  Object? _error;
  Timer? _debounce;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _role = _validRole(widget.initialRole);
    _status = _validStatus(widget.initialStatus);
    _load();
  }

  @override
  void didUpdateWidget(AdminUsersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The shell keeps this screen alive, so a new link arrives as an update.
    if (widget.initialRole == oldWidget.initialRole &&
        widget.initialStatus == oldWidget.initialStatus) {
      return;
    }
    final role = _validRole(widget.initialRole);
    final status = _validStatus(widget.initialStatus);
    if (role == _role && status == _status) return;
    _role = role;
    _status = status;
    _load();
  }

  /// Applies the chips' filters. Under the router the URL follows them, so a
  /// later link to the same filtered view is still a change.
  void _setFilters({required String? role, required String status}) {
    setState(() {
      _role = role;
      _status = status;
    });
    _load();
    GoRouter.maybeOf(context)
        ?.go(adminUsersLocation(role: role, status: status));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = !_loaded;
      _error = null;
    });
    try {
      final users = await ApiService.instance
          .adminListUsers(role: _role, query: _query, status: _status);
      // A newer filter or search superseded this request.
      if (!mounted || request != _request) return;
      setState(() {
        _users = users
          ..sort((a, b) => a.displayName
              .toLowerCase()
              .compareTo(b.displayName.toLowerCase()));
        _loading = false;
        _loaded = true;
      });
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _search(String value) {
    _query = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _load);
  }

  String? get _myId => context.read<AuthProvider>().user?.id;

  Future<void> _openForm([AdminUser? user]) async {
    final isSelf = user != null && user.id == _myId;
    final saved = await showFormSheet<bool>(
      context,
      title: user == null ? 'New user' : 'Edit ${user.displayName}',
      builder: (_) => _UserForm(user: user, isSelf: isSelf),
    );
    if (saved != true || !mounted) return;
    showToast(context, user == null ? 'User created' : 'User updated',
        kind: ToastKind.success);
    // Your own name and email also appear in the sidebar and account menu.
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    await Future.wait([
      _load(),
      if (isSelf && token != null) auth.getMe(token: token),
    ]);
  }

  Future<void> _resetPassword(AdminUser user) async {
    final isSelf = user.id == _myId;
    final saved = await showFormSheet<bool>(
      context,
      title: 'Reset password',
      builder: (_) => _PasswordForm(user: user, isSelf: isSelf),
    );
    if (saved != true || !mounted) return;
    if (isSelf) {
      // The API revokes every token of a user whose password is reset, this
      // session's included: sign in again now rather than fail on the next
      // request.
      final access = context.read<AdminAccess?>();
      if (access != null) {
        access.sessionEnded(kOwnPasswordChangedMessage);
      } else {
        await context.read<AuthProvider>().logout();
      }
      return;
    }
    showToast(context, 'Password updated for ${user.displayName}',
        kind: ToastKind.success);
  }

  Future<void> _setActive(AdminUser user, bool active) async {
    if (!active) {
      final ok = await confirmDialog(
        context,
        title: 'Deactivate ${user.displayName}?',
        message: 'They are signed out everywhere and cannot sign in until '
            'the account is activated again.',
        confirmLabel: 'Deactivate',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    await _run(
      () => ApiService.instance.adminUpdateUser(user.id, isActive: active),
      active ? 'Account activated' : 'Account deactivated',
    );
  }

  Future<void> _delete(AdminUser user) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${user.displayName}?',
      message: user.isStudent
          ? 'This removes them from every course and deletes their '
              'enrollments, submissions and attendance. It cannot be undone.'
          : 'This permanently deletes the account. It cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(
        () => ApiService.instance.adminDeleteUser(user.id), 'User deleted');
  }

  Future<void> _run(Future<Object?> Function() action, String done) async {
    try {
      await action();
      if (mounted) showToast(context, done, kind: ToastKind.success);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), kind: ToastKind.error);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final myId = context.watch<AuthProvider>().user?.id;

    return AppPage(
      title: 'Users',
      subtitle: _loaded
          ? '${_users.length} ${_users.length == 1 ? 'account' : 'accounts'}'
          : 'Students, teachers and admins',
      onRefresh: _load,
      actions: [
        FilledButton.icon(
          key: const Key('users-add'),
          onPressed: () => _openForm(),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: const Text('New user'),
        ),
      ],
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SearchField(
              key: const Key('users-search'),
              hint: 'Search name, email or phone',
              onChanged: _search,
            ),
            const SizedBox(height: AppSpacing.sm),
            FilterChips<String?>(
              key: const Key('users-role-filter'),
              options: const [
                FilterOption(null, 'All roles'),
                FilterOption('student', 'Students'),
                FilterOption('teacher', 'Teachers'),
                FilterOption('admin', 'Admins'),
              ],
              selected: _role,
              onSelected: (v) => _setFilters(role: v, status: _status),
            ),
            const SizedBox(height: AppSpacing.xs),
            FilterChips<String>(
              key: const Key('users-status-filter'),
              options: const [
                FilterOption('all', 'Any status'),
                FilterOption('active', 'Active'),
                FilterOption('inactive', 'Inactive'),
              ],
              selected: _status,
              onSelected: (v) => _setFilters(role: _role, status: v),
            ),
          ],
        ),
        AsyncBody(
          loading: _loading,
          error: _error,
          onRetry: _load,
          isEmpty: _users.isEmpty,
          empty: const EmptyState(
            icon: Icons.manage_accounts_outlined,
            title: 'No users match',
            message: 'Try another search or filter.',
          ),
          builder: (_) => AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (var i = 0; i < _users.length; i++) ...[
                  if (i > 0) const Divider(),
                  FadeSlideIn(
                    delay: AppMotion.delayFor(i),
                    offset: 8,
                    child: _UserRow(
                      user: _users[i],
                      isSelf: _users[i].id == myId,
                      onAction: (action) => switch (action) {
                        _UserAction.edit => _openForm(_users[i]),
                        _UserAction.password => _resetPassword(_users[i]),
                        _UserAction.activate => _setActive(_users[i], true),
                        _UserAction.deactivate => _setActive(_users[i], false),
                        _UserAction.delete => _delete(_users[i]),
                      },
                    ),
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

enum _UserAction { edit, password, activate, deactivate, delete }

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.isSelf,
    required this.onAction,
  });

  final AdminUser user;
  final bool isSelf;
  final ValueChanged<_UserAction> onAction;

  @override
  Widget build(BuildContext context) {
    final contact =
        [user.email, user.phone].where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      key: Key('user-row-${user.id}'),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      child: Row(
        children: [
          Avatar(name: user.displayName),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (contact.isNotEmpty)
                  Text(contact,
                      style: context.text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                const SizedBox(height: AppSpacing.xxs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    StatusBadge(
                      label: roleName(user.role),
                      icon: roleIcon(user.role),
                    ),
                    StatusBadge(
                      key: Key('user-status-${user.id}'),
                      label: user.isActive ? 'Active' : 'Inactive',
                      tone: user.isActive ? Tone.success : Tone.warning,
                    ),
                    if (isSelf)
                      const StatusBadge(label: 'You', tone: Tone.info),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<_UserAction>(
            key: Key('user-menu-${user.id}'),
            tooltip: 'Actions for ${user.displayName}',
            onSelected: onAction,
            itemBuilder: (_) => [
              const PopupMenuItem(
                key: Key('user-action-edit'),
                value: _UserAction.edit,
                child: Text('Edit'),
              ),
              const PopupMenuItem(
                key: Key('user-action-password'),
                value: _UserAction.password,
                child: Text('Reset password'),
              ),
              if (user.isActive)
                PopupMenuItem(
                  key: const Key('user-action-deactivate'),
                  value: _UserAction.deactivate,
                  // The API refuses to deactivate yourself (CANNOT_MODIFY_SELF).
                  enabled: !isSelf,
                  child: const Text('Deactivate'),
                )
              else
                const PopupMenuItem(
                  key: Key('user-action-activate'),
                  value: _UserAction.activate,
                  child: Text('Activate'),
                ),
              PopupMenuItem(
                key: const Key('user-action-delete'),
                value: _UserAction.delete,
                enabled: !isSelf,
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UserForm extends StatefulWidget {
  const _UserForm({required this.user, required this.isSelf});

  /// Null when creating.
  final AdminUser? user;
  final bool isSelf;

  @override
  State<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends State<_UserForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  final _password = TextEditingController();
  late String _role;
  bool _busy = false;
  String? _error;

  bool get _creating => widget.user == null;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _name = TextEditingController(text: u?.displayName ?? '');
    _email = TextEditingController(text: u?.email ?? '');
    _phone = TextEditingController(text: u?.phone ?? '');
    _role = u?.role ?? 'student';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final editing = widget.user;
    if (editing != null && _role != editing.role) {
      if (!await _confirmRoleChange(editing) || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = ApiService.instance;
    final name = _name.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    try {
      final user = widget.user;
      if (user == null) {
        await api.adminCreateUser(
          displayName: name,
          email: email,
          phone: phone,
          role: _role,
          password: _password.text,
        );
      } else {
        // PATCH only what changed.
        final changed = name != user.displayName ||
            email != user.email ||
            phone != user.phone ||
            _role != user.role;
        if (!changed) {
          if (mounted) Navigator.of(context).pop(false);
          return;
        }
        await api.adminUpdateUser(
          user.id,
          displayName: name != user.displayName ? name : null,
          email: email != user.email ? email : null,
          phone: phone != user.phone ? phone : null,
          role: _role != user.role ? _role : null,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  /// A role change can't be undone by changing it back: a student loses
  /// every course roster and chat membership, and an admin gains full control.
  Future<bool> _confirmRoleChange(AdminUser user) {
    final from = roleName(user.role);
    final to = roleName(_role);
    final consequences = [
      if (user.isStudent)
        'They are removed from every course roster and course chat. '
            'Changing the role back does not re-enroll them.',
      if (_role == 'admin')
        'Admins can manage every account, course and setting, including '
            'other admins.',
      if (user.role == 'admin') 'They lose access to the admin console.',
      'They are signed out everywhere.',
    ];
    return confirmDialog(
      context,
      title: 'Change ${user.displayName} from $from to $to?',
      message: consequences.join(' '),
      confirmLabel: 'Change role',
      destructive: user.isStudent || _role == 'admin' || user.role == 'admin',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            FormErrorBanner(
                key: const Key('user-form-error'), message: _error!),
            const SizedBox(height: AppSpacing.md),
          ],
          TextFormField(
            key: const Key('user-name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('user-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
            validator: (v) {
              final value = v?.trim() ?? '';
              if (value.isEmpty && _phone.text.trim().isEmpty) {
                return 'Enter an email or a phone number';
              }
              if (value.isNotEmpty && !value.contains('@')) {
                return 'Enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: const Key('user-phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone'),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            key: const Key('user-role'),
            initialValue: _role,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Role',
              helperText:
                  widget.isSelf ? 'You cannot change your own role' : null,
            ),
            items: [
              for (final r in _roles)
                DropdownMenuItem(value: r.value, child: Text(r.label)),
            ],
            onChanged: widget.isSelf
                ? null
                : (v) => setState(() => _role = v ?? _role),
          ),
          if (_creating) ...[
            const SizedBox(height: AppSpacing.md),
            PasswordField(
              key: const Key('user-password'),
              controller: _password,
              textInputAction: TextInputAction.done,
              validator: _validatePassword,
              autofillHints: const [AutofillHints.newPassword],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: BusyButton(
              key: const Key('user-save'),
              label: _creating ? 'Create user' : 'Save changes',
              busy: _busy,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}

String? _validatePassword(String? v) {
  if (v == null || v.isEmpty) return 'Enter a password';
  if (v.length < kMinAdminPasswordLength) {
    return 'Use at least $kMinAdminPasswordLength characters';
  }
  return null;
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm({required this.user, required this.isSelf});

  final AdminUser user;

  /// Resetting your own password also signs you out of this console.
  final bool isSelf;

  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiService.instance
          .adminResetPassword(widget.user.id, _password.text);
      if (mounted) Navigator.of(context).pop(true);
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
          Text(
            widget.isSelf
                ? 'Set a new password for your own account. You will be '
                    'signed out everywhere, this console included, and sign '
                    'in again with the new password.'
                : 'Set a new password for ${widget.user.displayName}. Share '
                    'it with them privately. They are signed out everywhere.',
            key: const Key('password-form-note'),
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_error != null) ...[
            FormErrorBanner(
                key: const Key('password-form-error'), message: _error!),
            const SizedBox(height: AppSpacing.md),
          ],
          PasswordField(
            key: const Key('user-new-password'),
            label: 'New password',
            controller: _password,
            validator: _validatePassword,
            onSubmitted: (_) => _save(),
            autofillHints: const [AutofillHints.newPassword],
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerRight,
            child: BusyButton(
              key: const Key('user-password-save'),
              label: 'Update password',
              busy: _busy,
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
