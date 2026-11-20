import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';

/// NOIR FLAME shared Outlined Text widget.
class OutlinedText extends StatelessWidget {
  const OutlinedText({
    super.key,
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

/// NOIR FLAME Underline-only Text Field with glowing orange focus.
class NoirTextField extends StatelessWidget {
  const NoirTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.prefixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.suffixIcon,
    this.validator,
    this.enabled = true,
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
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      enabled: enabled,
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
