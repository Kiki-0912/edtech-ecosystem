import 'package:edtech_app/admin/admin_access.dart';
import 'package:edtech_app/auth/auth_layout.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Admin console sign-in: email or phone plus password. There is deliberately
/// no sign-up and no SMS-code sign-in here.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    context.read<AdminAccess>().clearNotice();
    setState(() => _error = null);
    final id = _identifier.text.trim();
    final isEmail = id.contains('@');
    final ok = await auth.login(
      email: isEmail ? id : null,
      phone: isEmail ? null : id,
      password: _password.text,
    );
    if (!mounted) return;
    // On success the router admits an admin; AdminAccess signs anyone else
    // out again and sets the notice shown below.
    if (!ok) {
      setState(() => _error = friendlyError(auth.error ?? 'Sign in failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AuthProvider>().isLoading;
    final message = _error ?? context.watch<AdminAccess>().notice;

    return AuthLayout(
      title: 'Admin console',
      subtitle: 'Sign in with your administrator email or phone number.',
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (message != null) ...[
                FormErrorBanner(
                  key: const Key('admin-login-error'),
                  message: message,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextFormField(
                key: const Key('admin-login-identifier'),
                controller: _identifier,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.email,
                  AutofillHints.telephoneNumber,
                ],
                decoration: const InputDecoration(
                  labelText: 'Email or phone',
                  hintText: 'admin@example.edu',
                  prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                ),
                validator: (v) =>
                    requiredField(v, 'Please enter your email or phone'),
              ),
              const SizedBox(height: AppSpacing.md),
              PasswordField(
                key: const Key('admin-login-password'),
                controller: _password,
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Please enter your password'
                    : null,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 48,
                child: BusyButton(
                  key: const Key('admin-login-submit'),
                  label: 'Sign in',
                  busy: loading,
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
