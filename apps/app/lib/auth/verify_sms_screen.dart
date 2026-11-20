import 'dart:async';

import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/auth/auth_widgets.dart';
import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

typedef _OutlinedText = OutlinedText;
typedef _NoirTextField = NoirTextField;

// ─── NOIR FLAME — "VERIFY" SMS Screen ────────────────────────────────────

class VerifySmsScreen extends StatefulWidget {
  const VerifySmsScreen({super.key});

  @override
  State<VerifySmsScreen> createState() => _VerifySmsScreenState();
}

class _VerifySmsScreenState extends State<VerifySmsScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  // Hidden OTP backing controller
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();

  bool _codeSent = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  // ── Staggered animations ──────────────────────────────────────────────
  late final AnimationController _headerCtrl;
  late final AnimationController _subtitleCtrl;
  late final AnimationController _formCtrl;

  late final Animation<Offset> _headerSlide;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _subtitleSlide;
  late final Animation<double> _subtitleFade;
  late final Animation<Offset> _formSlide;
  late final Animation<double> _formFade;

  @override
  void initState() {
    super.initState();

    _headerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _subtitleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _formCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _headerSlide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOutBack));
    _headerFade = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);

    _subtitleSlide =
        Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero).animate(
            CurvedAnimation(parent: _subtitleCtrl, curve: Curves.easeOutBack));
    _subtitleFade = CurvedAnimation(parent: _subtitleCtrl, curve: Curves.easeOut);

    _formSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _formCtrl, curve: Curves.easeOutBack));
    _formFade = CurvedAnimation(parent: _formCtrl, curve: Curves.easeOut);

    _headerCtrl.forward();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _subtitleCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _formCtrl.forward();
    });

    _otpController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _subtitleCtrl.dispose();
    _formCtrl.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() => _resendSeconds = 60);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
      } else {
        if (mounted) setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _sendCode() async {
    if (_phoneController.text.trim().isEmpty) return;
    final auth = context.read<AuthProvider>();
    final success =
        await auth.sendSmsCode(phone: _phoneController.text.trim());
    if (!mounted) return;
    if (success) {
      setState(() {
        _codeSent = true;
        _otpController.clear();
      });
      _startResendTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification code sent'),
          backgroundColor: kSuccess,
        ),
      );
      // Auto-focus OTP field
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _otpFocusNode.requestFocus();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Could not send code'),
          backgroundColor: kError,
        ),
      );
    }
  }

  Future<void> _verify() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter all 6 digits'),
          backgroundColor: kError,
        ),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    final success = await auth.verifySmsCode(
      phone: _phoneController.text.trim(),
      code: code,
    );
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Invalid code'),
          backgroundColor: kError,
        ),
      );
    }
    // On success the router redirect handles navigation.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // ── Decorative: horizontal orange line across screen ──────────
          Positioned(
            top: 0,
            right: 0,
            child: CustomPaint(
              size: const Size(200, 240),
              painter: _VerifyFlamePainter(),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () {
                        if (_codeSent) {
                          setState(() {
                            _codeSent = false;
                            _otpController.clear();
                          });
                        } else {
                          context.pop();
                        }
                      },
                      child: const Icon(Icons.arrow_back_rounded,
                          color: Color(0xFF666666), size: 24),
                    ),
                    const SizedBox(height: 56),

                    // ── VERIFY title ──────────────────────────────────────
                    SlideTransition(
                      position: _headerSlide,
                      child: FadeTransition(
                        opacity: _headerFade,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'VERIFY',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 60,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -2,
                                height: 1.0,
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: _codeSent
                                  ? _OutlinedText(
                                      key: const ValueKey('otp'),
                                      text: '+CODE',
                                      fontSize: 48,
                                      strokeColor: kOrange500,
                                      strokeWidth: 1.8,
                                    )
                                  : _OutlinedText(
                                      key: const ValueKey('phone'),
                                      text: '+PHONE',
                                      fontSize: 48,
                                      strokeColor: kOrange500,
                                      strokeWidth: 1.8,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── Subtitle ──────────────────────────────────────────
                    SlideTransition(
                      position: _subtitleSlide,
                      child: FadeTransition(
                        opacity: _subtitleFade,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            _codeSent
                                ? 'Enter the 6-digit code sent to your phone'
                                : 'Confirm your phone to recover access',
                            key: ValueKey(_codeSent),
                            style: const TextStyle(
                              color: Color(0xFF666666),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 44),

                    // ── Form ──────────────────────────────────────────────
                    SlideTransition(
                      position: _formSlide,
                      child: FadeTransition(
                        opacity: _formFade,
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Phone field (disabled once code is sent)
                              _NoirTextField(
                                controller: _phoneController,
                                label: 'Phone Number',
                                prefixIcon: Icons.phone_rounded,
                                keyboardType: TextInputType.phone,
                                enabled: !_codeSent,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter your phone number';
                                  }
                                  return null;
                                },
                              ),

                              // OTP section (shown after code is sent)
                              AnimatedCrossFade(
                                duration: const Duration(milliseconds: 400),
                                crossFadeState: _codeSent
                                    ? CrossFadeState.showSecond
                                    : CrossFadeState.showFirst,
                                firstChild: const SizedBox(height: 0),
                                secondChild: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 36),
                                    const Text(
                                      'ENTER CODE',
                                      style: TextStyle(
                                        color: Color(0xFF666666),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // ── OTP boxes ──────────────────────────
                                    _OtpBoxRow(
                                      controller: _otpController,
                                      focusNode: _otpFocusNode,
                                    ),

                                    const SizedBox(height: 16),

                                    // Resend timer
                                    Center(
                                      child: _resendSeconds > 0
                                          ? Text(
                                              'Resend in ${_resendSeconds}s',
                                              style: const TextStyle(
                                                color: Color(0xFF666666),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            )
                                          : TextButton(
                                              onPressed: _sendCode,
                                              child: const Text(
                                                'Resend code',
                                                style: TextStyle(
                                                  color: kOrange500,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 36),

                              // ── Action button ───────────────────────────
                              Consumer<AuthProvider>(
                                builder: (context, auth, _) {
                                  return SizedBox(
                                    height: 56,
                                    child: FilledButton(
                                      onPressed: auth.isLoading
                                          ? null
                                          : (_codeSent ? _verify : _sendCode),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: kOrange500,
                                        foregroundColor: Colors.black,
                                        disabledBackgroundColor:
                                            kOrange500.withValues(alpha: 0.4),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                      child: auth.isLoading
                                          ? const SizedBox(
                                              height: 22,
                                              width: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: Colors.black,
                                              ),
                                            )
                                          : Text(
                                              _codeSent
                                                  ? 'VERIFY  ▶'
                                                  : 'SEND CODE  ▶',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 2,
                                              ),
                                            ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),

                              Center(
                                child: TextButton(
                                  onPressed: () {
                                    if (_codeSent) {
                                      setState(() {
                                        _codeSent = false;
                                        _otpController.clear();
                                      });
                                    } else {
                                      context.pop();
                                    }
                                  },
                                  child: Text(
                                    _codeSent
                                        ? 'Change phone number'
                                        : 'Back to sign in',
                                    style: const TextStyle(
                                      color: Color(0xFF666666),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── OTP Box Row ──────────────────────────────────────────────────────────
// 6 visual boxes backed by a single hidden TextField

class _OtpBoxRow extends StatelessWidget {
  const _OtpBoxRow({
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Hidden input field (positioned off-screen but technically visible)
        Opacity(
          opacity: 0,
          child: SizedBox(
            height: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
            ),
          ),
        ),

        // Visual boxes — tapping opens the keyboard via hidden field
        GestureDetector(
          onTap: () => focusNode.requestFocus(),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final digits = value.text.padRight(6, ' ');
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) {
                  final char = digits[i].trim();
                  final isFilled = char.isNotEmpty;
                  final isActive = i == value.text.length;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 48,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isFilled
                          ? kOrange500.withValues(alpha: 0.08)
                          : const Color(0xFF111111),
                      border: Border(
                        bottom: BorderSide(
                          color: isActive
                              ? kOrange500
                              : isFilled
                                  ? kOrange500.withValues(alpha: 0.6)
                                  : const Color(0xFF282828),
                          width: isActive ? 2.5 : 1.5,
                        ),
                      ),
                    ),
                    child: isFilled
                        ? Text(
                            char,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          )
                        : isActive
                            ? _BlinkingCursor()
                            : const SizedBox.shrink(),
                  );
                }),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Blinking cursor for OTP active box ──────────────────────────────────

class _BlinkingCursor extends StatefulWidget {
  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: Container(
        width: 2,
        height: 24,
        color: kOrange500,
      ),
    );
  }
}

// ─── Decorative painter for verify screen ────────────────────────────────

class _VerifyFlamePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Subtle triangle top-right
    final paint = Paint()
      ..color = kOrange500.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width * 0.3, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);

    // Orange edge
    final linePaint = Paint()
      ..color = kOrange500.withValues(alpha: 0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(size.width * 0.3, 0), Offset(size.width, size.height), linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
