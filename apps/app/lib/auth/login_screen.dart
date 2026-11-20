import 'dart:math' as math;

import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// ─── NOIR FLAME — "The Gate" Login Screen ──────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // ── Staggered animation controllers ──────────────────────────────────────
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

    _subtitleSlide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _subtitleCtrl, curve: Curves.easeOutBack));
    _subtitleFade = CurvedAnimation(parent: _subtitleCtrl, curve: Curves.easeOut);

    _formSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _formCtrl, curve: Curves.easeOutBack));
    _formFade = CurvedAnimation(parent: _formCtrl, curve: Curves.easeOut);

    // Stagger: 0ms → 100ms → 200ms
    _headerCtrl.forward();
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _subtitleCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _formCtrl.forward();
    });
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _subtitleCtrl.dispose();
    _formCtrl.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      phone: _phoneController.text.trim(),
      password: _passwordController.text,
    );
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Login failed'),
          backgroundColor: kError,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(kSpaceMd),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kRadiusMd)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // ── Decorative diagonal orange shape top-right ──────────────────
          Positioned(
            top: 0,
            right: 0,
            child: CustomPaint(
              size: const Size(220, 260),
              painter: _DiagonalFlamePainter(),
            ),
          ),

          // ── Main content ────────────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 72),

                    // ── EDTECH wordmark ───────────────────────────────────
                    SlideTransition(
                      position: _headerSlide,
                      child: FadeTransition(
                        opacity: _headerFade,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'EDTECH',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 56,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                                height: 1.0,
                              ),
                            ),
                            // Outlined orange stroke text
                            _OutlinedText(
                              text: 'ECOSYSTEM',
                              fontSize: 56,
                              strokeColor: kOrange500,
                              strokeWidth: 2.0,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // ── Subtitle ─────────────────────────────────────────
                    SlideTransition(
                      position: _subtitleSlide,
                      child: FadeTransition(
                        opacity: _subtitleFade,
                        child: const Text(
                          'Sign in to continue',
                          style: TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 48),

                    // ── Form (spring up from bottom) ──────────────────────
                    SlideTransition(
                      position: _formSlide,
                      child: FadeTransition(
                        opacity: _formFade,
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Phone field
                              _NoirTextField(
                                controller: _phoneController,
                                label: 'Phone',
                                prefixIcon: Icons.phone_rounded,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter your phone number';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),

                              // Password field
                              _NoirTextField(
                                controller: _passwordController,
                                label: 'Password',
                                prefixIcon: Icons.lock_rounded,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    color: const Color(0xFF666666),
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscurePassword = !_obscurePassword),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 40),

                              // SIGN IN button
                              Consumer<AuthProvider>(
                                builder: (context, auth, _) {
                                  return SizedBox(
                                    height: 56,
                                    child: FilledButton(
                                      onPressed: auth.isLoading ? null : _submit,
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
                                          : const Text(
                                              'SIGN IN  ▶',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 2,
                                              ),
                                            ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 14),

                              // Create account — ghost/outlined
                              SizedBox(
                                height: 52,
                                child: OutlinedButton(
                                  onPressed: () => context.push('/signup'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                        color: Color(0xFF282828), width: 1.5),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  child: const Text(
                                    'Create account',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Forgot / Verify SMS — text button
                              Center(
                                child: TextButton(
                                  onPressed: () => context.push('/verify-sms'),
                                  child: const Text(
                                    'Forgot password? Verify via SMS',
                                    style: TextStyle(
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

// ─── Decorative diagonal orange shape painter ─────────────────────────────

class _DiagonalFlamePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [kOrange500, kOrange700.withValues(alpha: 0.6)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.save();
    // Rotate 25° around the top-right corner
    canvas.translate(size.width, 0);
    canvas.rotate(25 * math.pi / 180);
    canvas.translate(-size.width, 0);

    final path = Path()
      ..moveTo(size.width * 0.1, -size.height * 0.1)
      ..lineTo(size.width * 1.1, -size.height * 0.1)
      ..lineTo(size.width * 1.1, size.height * 1.1)
      ..lineTo(size.width * 0.1, size.height * 0.6)
      ..close();

    canvas.drawPath(path, paint);
    canvas.restore();

    // Subtle accent line
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, size.height * 0.85),
        Offset(size.width * 0.75, 0), linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Outlined text widget ─────────────────────────────────────────────────

class _OutlinedText extends StatelessWidget {
  const _OutlinedText({
    required this.text,
    required this.fontSize,
    required this.strokeColor,
    this.strokeWidth = 1.5,
  });

  final String text;
  final double fontSize;
  final Color strokeColor;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Stroke layer
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
            height: 1.0,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..color = strokeColor,
          ),
        ),
        // Fill layer (transparent — outline only)
        Text(
          text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
            height: 1.0,
            color: Colors.transparent,
          ),
        ),
      ],
    );
  }
}

// ─── Shared underline-only text field ────────────────────────────────────

class _NoirTextField extends StatelessWidget {
  const _NoirTextField({
    required this.controller,
    required this.label,
    required this.prefixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.suffixIcon,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData prefixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Widget? suffixIcon;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF666666)),
        filled: true,
        fillColor: Colors.transparent,
        prefixIcon: Icon(prefixIcon, color: kOrange500, size: 20),
        suffixIcon: suffixIcon,
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF282828)),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF282828)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: kOrange500, width: 2),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: kError),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: kError, width: 2),
        ),
        disabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF1A1A1A)),
        ),
        errorStyle: const TextStyle(color: kError),
      ),
    );
  }
}
