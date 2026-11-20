import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';

/// Section title with a vertical orange accent bar on the left.
/// Optional [subtitle] below and [trailing] widget on the right.
class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Vertical orange accent bar
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            color: kOrange500,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),

        // Title + optional subtitle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? const Color(0xFFF7F7F7)
                      : const Color(0xFF0A0A0A),
                  letterSpacing: 0.1,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF9A9A9A),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Optional trailing widget
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}
