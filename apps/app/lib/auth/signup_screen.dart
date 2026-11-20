import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/auth/auth_widgets.dart';
import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

typedef _OutlinedText = OutlinedText;
typedef _NoirTextField = NoirTextField;

// ─── NOIR FLAME — "Create Account" Signup Screen ─────────────────────────

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = 'student';
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
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _subtitleCtrl.dispose();
    _formCtrl.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      displayName: _displayNameController.text.trim(),
      password: _passwordController.text,
      role: _role,
    );
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Registration failed'),
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
          // ── Decorative diagonal shape (flipped — bleeds from top-left) ──
          Positioned(
            top: 0,
            left: 0,
            child: CustomPaint(
              size: const Size(160, 200),
              painter: _SignupFlamePainter(),
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
                    // Back button row
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: Color(0xFF666666), size: 24),
                    ),
                    const SizedBox(height: 48),

                    // ── Title ─────────────────────────────────────────────
                    SlideTransition(
                      position: _headerSlide,
                      child: FadeTransition(
                        opacity: _headerFade,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'CREATE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 52,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                                height: 1.0,
                              ),
                            ),
                            const Text(
                              'ACCOUNT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 52,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(height: 2),
                            _OutlinedText(
                              text: 'ECOSYSTEM',
                              fontSize: 36,
                              strokeColor: kOrange500,
                              strokeWidth: 1.5,
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
                        child: const Text(
                          'Join the community',
                          style: TextStyle(
                            color: Color(0xFF666666),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

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
                              _NoirTextField(
                                controller: _displayNameController,
                                label: 'Full Name',
                                prefixIcon: Icons.person_rounded,
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter your name';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),

                              _NoirTextField(
                                controller: _emailController,
                                label: 'Email',
                                prefixIcon: Icons.email_rounded,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter your email';
                                  }
                                  if (!value.contains('@')) {
                                    return 'Please enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),

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
                                    return 'Please enter a password';
                                  }
                                  if (value.length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 28),

                              // ── Role chip selector ──────────────────────
                              const Text(
                                'I AM A',
                                style: TextStyle(
                                  color: Color(0xFF666666),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  _RoleChip(
                                    label: 'Student',
                                    icon: Icons.school_rounded,
                                    selected: _role == 'student',
                                    onTap: () => setState(() => _role = 'student'),
                                  ),
                                  const SizedBox(width: 10),
                                  _RoleChip(
                                    label: 'Teacher',
                                    icon: Icons.cast_for_education_rounded,
                                    selected: _role == 'teacher',
                                    onTap: () => setState(() => _role = 'teacher'),
                                  ),
                                  const SizedBox(width: 10),
                                  _RoleChip(
                                    label: 'Admin',
                                    icon: Icons.admin_panel_settings_rounded,
                                    selected: _role == 'admin',
                                    onTap: () => setState(() => _role = 'admin'),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 36),

                              // ── Submit button ───────────────────────────
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
                                              'CREATE ACCOUNT  ▶',
                                              style: TextStyle(
                                                fontSize: 15,
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
                                  onPressed: () => context.pop(),
                                  child: const Text(
                                    'Already have an account? Sign in',
                                    style: TextStyle(
                                      color: kOrange500,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
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

// ─── Role chip ────────────────────────────────────────────────────────────

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kOrange500 : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? kOrange500 : const Color(0xFF282828),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.black : const Color(0xFF666666),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : const Color(0xFF666666),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Decorative painter for signup (top-left bleeding) ───────────────────

class _SignupFlamePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kOrange500.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);

    // Orange edge line
    final linePaint = Paint()
      ..color = kOrange500.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(size.width, 0), Offset(0, size.height), linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Re-export shared widgets ─────────────────────────────────────────────
// (imported from login_screen.dart via the same package)
