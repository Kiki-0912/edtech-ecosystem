import 'package:edtech_app/auth/auth_layout.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Self-service registration. Only students and teachers can sign up; admin
/// accounts are provisioned (the API rejects role=admin on /auth/register).
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _role = 'student';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.register(
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      displayName: _name.text.trim(),
      password: _password.text,
      role: _role,
    );
    if (!mounted) return;
    if (ok) {
      showToast(context, 'Account created', kind: ToastKind.success);
      // The router's auth refresh moves us to "/".
    } else {
      showToast(context, friendlyError(auth.error ?? 'Sign up failed'),
          kind: ToastKind.error);
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AuthProvider>().isLoading;

    return AuthLayout(
      title: 'Create your account',
      subtitle: 'Join your classes, track deadlines and stay in touch.',
      onBack: _back,
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Already have an account?', style: context.text.bodyMedium),
          TextButton(onPressed: _back, child: const Text('Sign in')),
        ],
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('I am a', style: context.text.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<String>(
                key: const Key('signup-role'),
                segments: const [
                  ButtonSegment(
                      value: 'student',
                      icon: Icon(Icons.school_outlined),
                      label: Text('Student')),
                  ButtonSegment(
                      value: 'teacher',
                      icon: Icon(Icons.co_present_outlined),
                      label: Text('Teacher')),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('signup-name'),
                controller: _name,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                ),
                validator: (v) => requiredField(v, 'Please enter your name'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('signup-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!v.contains('@')) return 'Please enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('signup-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  prefixIcon: Icon(Icons.phone_outlined, size: 20),
                ),
                validator: (v) =>
                    requiredField(v, 'Please enter your phone number'),
              ),
              const SizedBox(height: AppSpacing.md),
              PasswordField(
                key: const Key('signup-password'),
                controller: _password,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Please enter a password';
                  if (v.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                height: 48,
                child: BusyButton(
                  key: const Key('signup-submit'),
                  label: 'Create account',
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
