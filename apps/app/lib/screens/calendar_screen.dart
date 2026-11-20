import 'package:edtech_app/auth/auth_provider.dart';
import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/calendar_event.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../widgets/deadline_card.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/staggered_reveal.dart';

/// NOIR FLAME — "The Schedule" Calendar
/// Features an interactive 7-day week ribbon, live event indicators, department filter chips, and flame cards.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  List<CalendarEvent> _events = [];
  List<Map<String, dynamic>> _departments = [];
  String? _selectedDepartmentId;
  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1.0,
    );
    _loadDepartments();
    _load();
  }

  Future<void> _loadDepartments() async {
    try {
      final departments = await ApiService.instance.getDepartments();
      if (!mounted) return;
      setState(() => _departments = departments);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events = await ApiService.instance.getCalendar(
        null,
        departmentId: _selectedDepartmentId,
      );
      if (!mounted) return;
      setState(() {
        _events = List<CalendarEvent>.from(events)
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
        _loading = false;
      });
      _fade.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _pickDepartment(String? value) async {
    HapticFeedback.selectionClick();
    setState(() => _selectedDepartmentId =
        (value == null || value.isEmpty) ? null : value);
    await _load();
  }

  /// Calculates the days for the current week strip.
  List<DateTime> get _currentWeekDays {
    final now = _selectedDate;
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return List.generate(7, (i) => monday.add(Duration(days: i)));
  }

  bool _hasEventOn(DateTime day) {
    return _events.any((e) => isSameDay(e.startsAt, day));
  }

  List<CalendarEvent> get _filteredEvents {
    // Show events on the selected date if any exist; otherwise show all upcoming events
    final onDay = _events.where((e) => isSameDay(e.startsAt, _selectedDate)).toList();
    if (onDay.isNotEmpty) return onDay;
    return _events;
  }

  Future<void> _showEventDialog({CalendarEvent? event}) async {
    HapticFeedback.mediumImpact();
    final draft = await showDialog<_EventDraft>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusXl),
          side: BorderSide(color: kBorder, width: 1),
        ),
        child: _EventEditorDialog(
          event: event,
          departments: _departments,
          initialDepartmentId: _selectedDepartmentId,
        ),
      ),
    );
    if (draft == null || !mounted) return;

    setState(() => _saving = true);
    final api = ApiService.instance;
    try {
      if (draft.delete && event != null) {
        await api.deleteCalendarEvent(event.id);
      } else if (event == null) {
        await api.createCalendarEvent(
          title: draft.title,
          kind: draft.kind,
          startsAt: draft.startsAt,
          endsAt: draft.endsAt,
          departmentId: draft.departmentId,
        );
      } else {
        await api.updateCalendarEvent(
          id: event.id,
          title: draft.title,
          kind: draft.kind,
          startsAt: draft.startsAt,
          endsAt: draft.endsAt,
          departmentId: draft.departmentId,
        );
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(draft.delete ? 'Event deleted' : 'Calendar updated'),
          backgroundColor: kPrimary,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(kSpaceMd),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMd)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save event: $e'),
          backgroundColor: kError,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(kSpaceMd),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMd)),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().user?.role == 'admin';
    final week = _currentWeekDays;
    final displayEvents = _filteredEvents;

    return Scaffold(
      backgroundColor: kBackground,
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: _saving ? null : () => _showEventDialog(),
              backgroundColor: kPrimary,
              elevation: 4,
              child: const Icon(Icons.add, color: Colors.black, size: 26),
            )
          : null,
      body: FadeTransition(
        opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
        child: RefreshIndicator(
          onRefresh: _load,
          color: kPrimary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            children: [
              // ── Header ───────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TIMETABLE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: kPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Calendar',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                          color: kTextPrimary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: kTextSecondary, size: 22),
                    tooltip: 'Refresh',
                    onPressed: _load,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── 7-Day Interactive Week Strip ─────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kBorder, width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: week.map((day) {
                    final isSelected = isSameDay(day, _selectedDate);
                    final isToday = isSameDay(day, DateTime.now());
                    final hasEvent = _hasEventOn(day);
                    final weekdayLabel = const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.weekday - 1];

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selectedDate = day);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? kPrimary
                              : isToday
                                  ? kPrimary.withValues(alpha: 0.12)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          border: isToday && !isSelected
                              ? Border.all(color: kPrimary.withValues(alpha: 0.5), width: 1.2)
                              : null,
                          boxShadow: isSelected ? [flameShadow(0.8)] : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              weekdayLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isSelected
                                    ? Colors.black
                                    : isToday
                                        ? kPrimary
                                        : kTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: isSelected
                                    ? Colors.black
                                    : isToday
                                        ? kPrimary
                                        : kTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: hasEvent
                                    ? (isSelected ? Colors.black : kPrimary)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 16),

              // ── Department Filter Pills ──────────────────────────────────
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _FilterChip(
                      label: 'All Depts',
                      selected: _selectedDepartmentId == null,
                      onTap: () => _pickDepartment(null),
                    ),
                    const SizedBox(width: 8),
                    ..._departments.map((dept) {
                      final id = dept['id']?.toString() ?? '';
                      final isSel = _selectedDepartmentId == id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _FilterChip(
                          label: dept['code']?.toString() ?? dept['name']?.toString() ?? '',
                          selected: isSel,
                          onTap: () => _pickDepartment(id),
                        ),
                      );
                    }),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Event Feed ────────────────────────────────────────────────
              if (_loading)
                const Column(
                  children: [SkeletonCard(), SkeletonCard(), SkeletonCard()],
                )
              else if (_error != null)
                _ErrorState(error: _error!, onRetry: _load)
              else if (displayEvents.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kBorder),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(Icons.event_available_rounded, size: 30, color: kPrimary),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'NO SESSIONS SCHEDULED',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: kTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your calendar is clear on this date.',
                        style: TextStyle(color: kTextSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                )
              else
                StaggeredReveal(
                  childCount: displayEvents.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: DeadlineCard(
                      event: displayEvents[index],
                      onTap: isAdmin
                          ? () => _showEventDialog(event: displayEvents[index])
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kPrimary : kSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? kPrimary : kBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : kTextPrimary,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _EventDraft {
  const _EventDraft({
    required this.title,
    required this.kind,
    required this.startsAt,
    required this.endsAt,
    required this.departmentId,
    this.delete = false,
  });

  final String title;
  final String kind;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? departmentId;
  final bool delete;
}

class _EventEditorDialog extends StatefulWidget {
  const _EventEditorDialog({
    required this.event,
    required this.departments,
    required this.initialDepartmentId,
  });

  final CalendarEvent? event;
  final List<Map<String, dynamic>> departments;
  final String? initialDepartmentId;

  @override
  State<_EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends State<_EventEditorDialog> {
  late final TextEditingController _titleCtrl;
  late String _kind;
  String? _departmentId;
  late DateTime _startsAt;
  DateTime? _endsAt;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _titleCtrl = TextEditingController(text: event?.title ?? '');
    _kind = event?.kind ?? 'class';
    _departmentId = event?.departmentId ?? widget.initialDepartmentId;
    _startsAt = event?.startsAt ?? DateTime.now().add(const Duration(days: 1));
    _endsAt = event?.endsAt;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime value) {
    final date = '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final time = '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: kPrimary,
              onPrimary: Colors.black,
              surface: kSurface,
              onSurface: kTextPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: kPrimary,
              onPrimary: Colors.black,
              surface: kSurface,
              onSurface: kTextPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    return DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? initial.hour,
      time?.minute ?? initial.minute,
    );
  }

  void _submit({bool delete = false}) {
    Navigator.pop(
      context,
      _EventDraft(
        title: _titleCtrl.text.trim().isEmpty ? 'Untitled event' : _titleCtrl.text.trim(),
        kind: _kind,
        startsAt: _startsAt,
        endsAt: _endsAt,
        departmentId: _departmentId,
        delete: delete,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.event == null ? 'ADD EVENT' : 'EDIT EVENT',
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              letterSpacing: 0.5,
              color: kPrimary,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Event Title'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: 'class', child: Text('Class Session')),
              DropdownMenuItem(value: 'assignment', child: Text('Assignment Deadline')),
              DropdownMenuItem(value: 'quiz', child: Text('Exam / Assessment')),
              DropdownMenuItem(value: 'institution', child: Text('Institutional')),
            ],
            onChanged: (val) => setState(() => _kind = val ?? 'class'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event, size: 18, color: kPrimary),
              label: Text('Starts: ${_fmt(_startsAt)}', style: TextStyle(color: kTextPrimary)),
              onPressed: () async {
                final picked = await _pickDateTime(_startsAt);
                if (picked != null) setState(() => _startsAt = picked);
              },
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              if (widget.event != null)
                TextButton(
                  onPressed: () => _submit(delete: true),
                  child: const Text('Delete', style: TextStyle(color: kError, fontWeight: FontWeight.w700)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: kTextSecondary)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => _submit(),
                style: FilledButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  widget.event == null ? 'Create' : 'Save',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: kError),
          const SizedBox(height: 12),
          Text(error, style: TextStyle(color: kTextSecondary, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: kPrimary, foregroundColor: Colors.black),
            child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
