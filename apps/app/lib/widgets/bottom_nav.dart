import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:edtech_app/theme.dart';

/// NOIR FLAME — floating pill nav bar.
/// First 5 items live in the bar; items 5–8 open in a "More" bottom sheet.
class BottomNav extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const BottomNav({super.key, required this.selectedIndex, required this.onTap});

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> with SingleTickerProviderStateMixin {
  // ── item catalogue ────────────────────────────────────────────────────────
  static const _items = [
    {'icon': Icons.dashboard_rounded,       'label': 'Home'},
    {'icon': Icons.school_rounded,          'label': 'Courses'},
    {'icon': Icons.calendar_month_rounded,  'label': 'Calendar'},
    {'icon': Icons.chat_bubble_rounded,     'label': 'Chat'},
    {'icon': Icons.verified_rounded,        'label': 'Integrity'},
    // ── overflow (shown in "More" sheet) ──
    {'icon': Icons.people_rounded,          'label': 'Students'},
    {'icon': Icons.business_rounded,        'label': 'Departments'},
    {'icon': Icons.check_circle_rounded,    'label': 'Attendance'},
    {'icon': Icons.note_rounded,            'label': 'Notes'},
  ];

  /// Number of items rendered directly in the bar (slot 5 is the "⠿" button).
  static const _barCount = 5;

  void _handleTap(int index) {
    HapticFeedback.selectionClick();
    widget.onTap(index);
  }

  /// Opens the "More" sheet for overflow items (indices 5–8).
  void _openMore() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MoreSheet(
        items: _items.sublist(5),
        startIndex: 5,
        selectedIndex: widget.selectedIndex,
        onTap: (i) {
          Navigator.pop(context);
          _handleTap(i);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // "More" button is highlighted whenever the active index is in the overflow.
    final moreActive = widget.selectedIndex >= _barCount;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: kOrange500.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: kOrange500.withValues(alpha: 0.28),
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Row(
          children: [
            // ── 5 primary slots ──────────────────────────────────────────
            ...List.generate(_barCount, (i) {
              final item = _items[i];
              return Expanded(
                child: _NavSlot(
                  icon: item['icon'] as IconData,
                  label: item['label'] as String,
                  isSelected: widget.selectedIndex == i,
                  onTap: () => _handleTap(i),
                ),
              );
            }),
            // ── "More" (⠿) slot ──────────────────────────────────────────
            Expanded(
              child: _NavSlot(
                icon: Icons.apps_rounded,
                label: 'More',
                isSelected: moreActive,
                onTap: _openMore,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Individual tab slot ────────────────────────────────────────────────────

class _NavSlot extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavSlot({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          width: isSelected ? 54 : 40,
          height: isSelected ? 36 : 32,
          decoration: BoxDecoration(
            color: isSelected ? kOrange500 : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: kOrange500.withValues(alpha: 0.5),
                      blurRadius: 12,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 280),
                curve: Curves.elasticOut,
                scale: isSelected ? 1.1 : 1.0,
                child: Icon(
                  icon,
                  size: 18,
                  color: isSelected ? Colors.white : const Color(0xFF666666),
                ),
              ),
              if (!isSelected) ...[
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF666666),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── "More" bottom sheet ────────────────────────────────────────────────────

class _MoreSheet extends StatelessWidget {
  final List<Map<String, Object>> items;
  final int startIndex;
  final int selectedIndex;
  final void Function(int) onTap;

  const _MoreSheet({
    required this.items,
    required this.startIndex,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: kOrange500.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: kOrange500.withValues(alpha: 0.15),
            blurRadius: 32,
            spreadRadius: 0,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // Header
              Row(
                children: [
                  Text(
                    'MORE',
                    style: TextStyle(
                      color: kOrange500,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 3-col grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, i) {
                  final globalIndex = startIndex + i;
                  final isSelected = selectedIndex == globalIndex;
                  final item = items[i];
                  return GestureDetector(
                    onTap: () => onTap(globalIndex),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutBack,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? kOrange500.withValues(alpha: 0.15)
                            : const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? kOrange500.withValues(alpha: 0.6)
                              : const Color(0xFF282828),
                          width: 1,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: kOrange500.withValues(alpha: 0.2),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                )
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            item['icon'] as IconData,
                            size: 28,
                            color: isSelected ? kOrange500 : kOrange500.withValues(alpha: 0.7),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item['label'] as String,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white : const Color(0xFF9A9A9A),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
