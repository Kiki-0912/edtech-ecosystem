import 'package:edtech_app/auth/auth_layout.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/config.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/ui/ui.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Whether the "Sign in with a code" entry point is shown. Offline, codes are
/// simulated; online it needs [AppConfig.smsSignIn], because without an SMS
/// provider the API never delivers the code and the flow cannot finish.
bool get smsSignInAvailable =>
    ApiService.instance.isOffline || AppConfig.smsSignIn;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.login(
      phone: _phone.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    // On success the router's auth refresh navigates to "/".
    if (!ok) {
      showToast(
        context,
        friendlyError(auth.error ?? 'Sign in failed'),
        kind: ToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AuthProvider>().isLoading;

    return AuthLayout(
      title: 'Welcome back',
      subtitle: 'Sign in with your phone number and password.',
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('New here?', style: context.text.bodyMedium),
          TextButton(
            key: const Key('login-create-account'),
            onPressed: () => context.push('/signup'),
            child: const Text('Create an account'),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const Key('login-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+1 555 000 1002',
                  prefixIcon: Icon(Icons.phone_outlined, size: 20),
                ),
                validator: (v) =>
                    requiredField(v, 'Please enter your phone number'),
              ),
              const SizedBox(height: AppSpacing.md),
              PasswordField(
                key: const Key('login-password'),
                controller: _password,
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Please enter your password'
                    : null,
                onSubmitted: (_) => _submit(),
              ),
              if (smsSignInAvailable)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const Key('login-sms'),
                    onPressed: () => context.push('/verify-sms'),
                    child: const Text('Forgot password? Sign in with a code'),
                  ),
                ),
              const SizedBox(height: AppSpacing.xs),
              SizedBox(
                height: 48,
                child: BusyButton(
                  key: const Key('login-submit'),
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
