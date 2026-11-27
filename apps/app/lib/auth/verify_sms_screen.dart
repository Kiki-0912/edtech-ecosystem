import 'dart:async';

import 'package:edtech_app/auth/auth_layout.dart';
import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/auth/login_screen.dart' show smsSignInAvailable;
import 'package:edtech_app/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Two-step sign-in by one-time SMS code: phone → 6-digit code.
class VerifySmsScreen extends StatefulWidget {
  const VerifySmsScreen({super.key});

  @override
  State<VerifySmsScreen> createState() => _VerifySmsScreenState();
}

class _VerifySmsScreenState extends State<VerifySmsScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  bool _codeSent = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phone.dispose();
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(
        () => _resendSeconds = _resendSeconds <= 1 ? 0 : _resendSeconds - 1,
      );
      if (_resendSeconds == 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (_phone.text.trim().isEmpty) {
      showToast(context, 'Enter your phone number', kind: ToastKind.error);
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendSmsCode(phone: _phone.text.trim());
    if (!mounted) return;
    if (ok) {
      setState(() {
        _codeSent = true;
        _code.clear();
      });
      _startResendTimer();
      showToast(context, 'Verification code sent', kind: ToastKind.success);
      _codeFocus.requestFocus();
    } else {
      showToast(
        context,
        friendlyError(auth.error ?? 'Could not send code'),
        kind: ToastKind.error,
      );
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6) {
      showToast(context, 'Enter all 6 digits', kind: ToastKind.error);
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifySmsCode(
      phone: _phone.text.trim(),
      code: _code.text.trim(),
    );
    if (!mounted) return;
    // On success the router's auth refresh navigates to "/".
    if (!ok) {
      showToast(
        context,
        friendlyError(auth.error ?? 'Invalid code'),
        kind: ToastKind.error,
      );
    }
  }

  void _back() {
    if (_codeSent) {
      _resendTimer?.cancel();
      setState(() {
        _codeSent = false;
        _resendSeconds = 0;
      });
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<AuthProvider>().isLoading;

    return AuthLayout(
      title: _codeSent ? 'Enter the code' : 'Sign in with a code',
      subtitle: _codeSent
          ? 'We sent a 6-digit code to ${_phone.text.trim()}.'
          : 'We\'ll text a one-time code to your phone number.',
      onBack: _back,
      footer: Center(
        child: TextButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/login'),
          child: const Text('Back to sign in'),
        ),
      ),
      child: !smsSignInAvailable
          ? const FormErrorBanner(
              key: Key('sms-unavailable'),
              message: 'Sign-in codes are not available on this server. '
                  'Sign in with your password, or ask an admin to reset it.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StepIndicator(step: _codeSent ? 1 : 0),
                const SizedBox(height: AppSpacing.lg),
                if (!_codeSent) ...[
                  TextField(
                    key: const Key('sms-phone'),
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    onSubmitted: (_) => _sendCode(),
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      prefixIcon: Icon(Icons.phone_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    height: 48,
                    child: BusyButton(
                      key: const Key('sms-send'),
                      label: 'Send code',
                      busy: loading,
                      onPressed: _sendCode,
                    ),
                  ),
                ] else ...[
                  OtpInput(
                    controller: _code,
                    focusNode: _codeFocus,
                    onCompleted: (_) => _verify(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    height: 48,
                    child: BusyButton(
                      key: const Key('sms-verify'),
                      label: 'Verify and sign in',
                      busy: loading,
                      onPressed: _verify,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: _resendSeconds > 0
                        ? Text(
                            'Resend code in ${_resendSeconds}s',
                            style: context.text.bodySmall,
                          )
                        : TextButton(
                            key: const Key('sms-resend'),
                            onPressed: loading ? null : _sendCode,
                            child: const Text('Resend code'),
                          ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget dot(int i, String label) {
      final done = i < step;
      final active = i == step;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (done || active) ? c.accent : c.surfaceMuted,
            ),
            child: done
                ? Icon(Icons.check_rounded, size: 14, color: c.onAccent)
                : Text(
                    '${i + 1}',
                    style: context.text.labelSmall?.copyWith(
                      color: active ? c.onAccent : c.textMuted,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: active ? c.textPrimary : c.textMuted,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        dot(0, 'Phone'),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Divider(color: step > 0 ? c.accent : c.border),
          ),
        ),
        dot(1, 'Code'),
      ],
    );
  }
}

/// Six boxes drawn over a single hidden numeric field.
class OtpInput extends StatelessWidget {
  const OtpInput({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onCompleted,
    this.length = 6,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onCompleted;
  final int length;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Verification code',
      textField: true,
      child: Stack(
        children: [
          // Real input: invisible but focusable, receives the keyboard.
          Opacity(
            opacity: 0,
            child: SizedBox(
              height: 1,
              child: TextField(
                key: const Key('sms-code'),
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(length),
                ],
                onChanged: (v) {
                  if (v.length == length) onCompleted?.call(v);
                },
              ),
            ),
          ),
          GestureDetector(
            onTap: focusNode.requestFocus,
            child: ListenableBuilder(
              listenable: Listenable.merge([controller, focusNode]),
              builder: (context, _) {
                final text = controller.text;
                return Row(
                  children: [
                    for (var i = 0; i < length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: AppRadius.mdAll,
                            border: Border.all(
                              color: focusNode.hasFocus && i == text.length
                                  ? c.accent
                                  : (i < text.length ? c.textMuted : c.border),
                              width: focusNode.hasFocus && i == text.length
                                  ? 1.5
                                  : 1,
                            ),
                          ),
                          child: Text(
                            i < text.length ? text[i] : '',
                            style: context.text.headlineSmall,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
