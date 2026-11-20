import 'dart:async';

import 'package:edtech_app/formats.dart';
import 'package:edtech_app/models/assignment.dart';
import 'package:edtech_app/models/college.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/services/api_service.dart';
import 'package:edtech_app/theme.dart';
import 'package:edtech_app/widgets/bounce_tap.dart';
import 'package:edtech_app/widgets/floating_shapes.dart';
import 'package:edtech_app/widgets/responsive_grid.dart';
import 'package:edtech_app/widgets/skeleton_loader.dart';
import 'package:flutter/material.dart';

/// Courses — editorial header with search, one hero course card, then the rest
/// of the enrolment as compact cards. Layout follows the Sleek design; covers
/// are generated from `theme.dart` gradients so the app stays offline-safe.
class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key});

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen> {
  List<Course> _courses = <Course>[];
  College? _college;
  final Map<String, Assignment?> _nextDue = <String, Assignment?>{};
  Timer? _liveTimer;
  bool _loading = true;
  String? _error;
  bool _searching = false;
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _liveTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshCollegeSilently(),
    );
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshCollegeSilently() async {
    try {
      final college = await ApiService.instance.getCollege();
      if (!mounted) return;
      if (college != null) setState(() => _college = college);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.instance.getCourses(),
        ApiService.instance.getCollege(),
      ]);
      if (!mounted) return;
      final courses = results[0] as List<Course>;
      setState(() {
        _courses = courses;
        _college = results[1] as College? ?? College.demo;
        _loading = false;
      });
      _loadDueDates(courses);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Resolves the earliest open assignment per course. Failures are swallowed
  /// per course so one bad request cannot blank the screen.
  Future<void> _loadDueDates(List<Course> courses) async {
    final entries = await Future.wait(courses.map((course) async {
      try {
        final assignments = await ApiService.instance.getAssignments(course.id);
        final open = assignments.where((a) => a.status != 'draft').toList()
          ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
        return MapEntry<String, Assignment?>(course.id, open.isEmpty ? null : open.first);
      } catch (_) {
        return MapEntry<String, Assignment?>(course.id, null);
      }
    }));
    if (!mounted) return;
    setState(() => _nextDue.addAll(Map<String, Assignment?>.fromEntries(entries)));
  }

  List<Course> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _courses;
    return _courses.where((course) {
      return course.title.toLowerCase().contains(q) ||
          course.code.toLowerCase().contains(q) ||
          (course.teacherName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Color _courseColor(int index) => kBrandColors[index % kBrandColors.length];

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final featured = visible.isEmpty ? null : visible.first;
    final rest = visible.length > 1 ? visible.sublist(1) : const <Course>[];

    return RefreshIndicator(
      onRefresh: _load,
      color: kPrimary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: kSpaceLg, vertical: kSpaceMd),
        children: [
          _Header(
            subtitle: _courses.isEmpty
                ? 'Loading enrolment'
                : '${_courses.first.term} · ${_courses.length} '
                    '${_courses.length == 1 ? 'course' : 'courses'}',
            searching: _searching,
            query: _query,
            controller: _searchCtrl,
            onToggleSearch: () {
              setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _query = '';
                  _searchCtrl.clear();
                }
              });
            },
            onQueryChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: kSpaceLg),
          if (_loading)
            const Column(
              children: [
                SkeletonBox(height: 300, borderRadius: BorderRadius.all(Radius.circular(20))),
                SizedBox(height: kSpaceMd),
                SkeletonCard(),
                SizedBox(height: kSpaceSm),
                SkeletonCard(),
              ],
            )
          else if (_error != null)
            _ErrorState(error: _error!, onRetry: _load)
          else if (_courses.isEmpty)
            const _EmptyCourses()
          else if (visible.isEmpty)
            _NoSearchResults(query: _query)
          else ...[
            _FeaturedCourse(
              course: featured!,
              color: _courseColor(0),
              nextDue: _nextDue[featured.id],
            ),
            if (rest.isNotEmpty) ...[
              const SizedBox(height: kSpaceMd),
              for (var i = 0; i < rest.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: kSpaceSm),
                  child: _CourseRow(
                    course: rest[i],
                    color: _courseColor(i + 1),
                    nextDue: _nextDue[rest[i].id],
                  ),
                ),
            ],
          ],
          if (_college != null) ...[
            const SizedBox(height: kSpaceXl),
            _PageHeader(
              title: 'Departments',
              subtitle: 'Every programme offered at ${_college!.shortName}',
            ),
            const SizedBox(height: kSpaceMd),
            ..._programmePanels(_college!),
          ],
          const SizedBox(height: kSpaceXl),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String subtitle;
  final bool searching;
  final String query;
  final TextEditingController controller;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onQueryChanged;

  const _Header({
    required this.subtitle,
    required this.searching,
    required this.query,
    required this.controller,
    required this.onToggleSearch,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle.toUpperCase(),
                    style: context.overline.copyWith(letterSpacing: 1.1),
                  ),
                  const SizedBox(height: kSpaceXs),
                  Text(
                    'My Courses',
                    style: TextStyle(
                      fontSize: 44,
                      height: 1.05,
                      letterSpacing: -1.2,
                      fontWeight: FontWeight.w800,
                      color: kTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: kSpaceSm),
            BounceTap(
              onTap: onToggleSearch,
              child: Tooltip(
                message: searching ? 'Close search' : 'Search courses',
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: searching ? tintOf(kPrimary, 0.12) : kCard,
                    shape: BoxShape.circle,
                    border: Border.all(color: searching ? kPrimary : kBorder),
                  ),
                  child: Icon(
                    searching ? Icons.close_rounded : Icons.search_rounded,
                    color: searching ? kPrimary : kTextPrimary,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (searching) ...[
          const SizedBox(height: kSpaceMd),
          TextField(
            controller: controller,
            autofocus: true,
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              hintText: 'Search by course, code or teacher',
              prefixIcon: Icon(Icons.search_rounded, color: kTextSecondary),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: Icon(Icons.close_rounded, color: kTextSecondary, size: 18),
                      onPressed: () {
                        controller.clear();
                        onQueryChanged('');
                      },
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Hero card for the first visible course: generated cover, identity block and
/// the next-deadline footer.
class _FeaturedCourse extends StatelessWidget {
  final Course course;
  final Color color;
  final Assignment? nextDue;

  const _FeaturedCourse({
    required this.course,
    required this.color,
    required this.nextDue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: kBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Generated cover — stands in for the mockup's stock photograph.
          SizedBox(
            height: 200,
            width: double.infinity,
            child: FloatingShapes(
              child: Container(
                decoration: BoxDecoration(
                  gradient: livelyGradient(color, shadeOf(color, 0.35)),
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(kSpaceLg),
                    child: Text(
                      course.code,
                      style: TextStyle(
                        fontSize: 40,
                        height: 1,
                        letterSpacing: -1,
                        fontWeight: FontWeight.w900,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(kSpaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: kSpaceSm),
                    Expanded(
                      child: Text(
                        '${course.code} · ${course.term}'.toUpperCase(),
                        style: context.overline.copyWith(letterSpacing: 1.1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: kSpaceSm),
                Text(
                  course.title,
                  style: TextStyle(
                    fontSize: 30,
                    height: 1.12,
                    letterSpacing: -0.8,
                    fontWeight: FontWeight.w800,
                    color: kTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  course.teacherName ?? 'Unassigned',
                  style: context.body2.copyWith(color: kTextSecondary),
                ),
                const SizedBox(height: kSpaceMd),
                Divider(height: 1, color: kDivider),
                const SizedBox(height: kSpaceMd),
                if (nextDue != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Next deadline'.toUpperCase(),
                              style: context.overline.copyWith(letterSpacing: 1.1),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              shortDate(nextDue!.dueAt),
                              style: TextStyle(
                                fontSize: 24,
                                letterSpacing: -0.5,
                                fontWeight: FontWeight.w800,
                                fontFeatures: [FontFeature.tabularFigures()],
                                color: kTextPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: kSpaceSm),
                      Flexible(
                        child: Text(
                          nextDue!.title,
                          textAlign: TextAlign.end,
                          style: context.body2.copyWith(
                            fontWeight: FontWeight.w600,
                            color: kTextPrimary,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Open assignments'.toUpperCase(),
                              style: context.overline.copyWith(letterSpacing: 1.1),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${course.openAssignmentCount ?? 0}',
                              style: TextStyle(
                                fontSize: 24,
                                letterSpacing: -0.5,
                                fontWeight: FontWeight.w800,
                                fontFeatures: [FontFeature.tabularFigures()],
                                color: kTextPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: kSpaceSm),
                      Text(
                        'none due yet',
                        textAlign: TextAlign.end,
                        style: context.body2.copyWith(color: kTextSecondary),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact card for every course after the hero.
class _CourseRow extends StatelessWidget {
  final Course course;
  final Color color;
  final Assignment? nextDue;

  const _CourseRow({
    required this.course,
    required this.color,
    required this.nextDue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceSm),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Generated thumbnail, same slot as the mockup's square photo.
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: livelyGradient(color, shadeOf(color, 0.35)),
              borderRadius: BorderRadius.circular(kRadiusSm),
            ),
            alignment: Alignment.center,
            child: Text(
              course.code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: kSpaceMd),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: kSpaceXs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: kSpaceSm),
                      Expanded(
                        child: Text(
                          course.code.toUpperCase(),
                          style: context.overline.copyWith(letterSpacing: 1.1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    course.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: kTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    course.teacherName ?? 'Unassigned',
                    style: context.body2.copyWith(color: kTextSecondary),
                  ),
                  const SizedBox(height: kSpaceXs),
                  if (nextDue != null)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Next due ',
                            style: context.body2.copyWith(color: kTextSecondary),
                          ),
                          TextSpan(
                            text: shortDate(nextDue!.dueAt),
                            style: context.body2.copyWith(
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [FontFeature.tabularFigures()],
                              color: kTextPrimary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      '${course.openAssignmentCount ?? 0} open '
                      '${course.openAssignmentCount == 1 ? 'assignment' : 'assignments'}',
                      style: context.body2.copyWith(color: kTextSecondary),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _PageHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.h4.copyWith(fontWeight: FontWeight.w800, color: kTextPrimary),
        ),
        const SizedBox(height: kSpaceXs),
        Text(
          subtitle,
          style: context.body2.copyWith(fontSize: 13, color: kTextSecondary),
        ),
      ],
    );
  }
}

class _EmptyCourses extends StatelessWidget {
  const _EmptyCourses();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceXl),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        children: [
          const Text('🌱', style: TextStyle(fontSize: 48)),
          const SizedBox(height: kSpaceMd),
          Text(
            'No courses yet',
            style: context.h4.copyWith(fontWeight: FontWeight.w800, color: kTextPrimary),
          ),
          const SizedBox(height: kSpaceSm),
          Text(
            'Courses you enroll in will appear here.',
            textAlign: TextAlign.center,
            style: context.body2.copyWith(color: kTextSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  final String query;
  const _NoSearchResults({required this.query});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(kSpaceXl),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        children: [
          const Text('🔍', style: TextStyle(fontSize: 44)),
          const SizedBox(height: kSpaceMd),
          Text(
            'No matches for "$query"',
            textAlign: TextAlign.center,
            style: context.h5.copyWith(fontWeight: FontWeight.w800, color: kTextPrimary),
          ),
          const SizedBox(height: kSpaceXs),
          Text(
            'Try a course code, title or teacher name.',
            textAlign: TextAlign.center,
            style: context.body2.copyWith(color: kTextSecondary, fontSize: 14),
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
    return Container(
      padding: const EdgeInsets.all(kSpaceXl),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: kDivider),
      ),
      child: Column(
        children: [
          const Text('😵', style: TextStyle(fontSize: 44)),
          const SizedBox(height: kSpaceMd),
          Text(
            error,
            textAlign: TextAlign.center,
            style: context.body2.copyWith(color: kTextSecondary, fontSize: 13),
          ),
          const SizedBox(height: kSpaceLg),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
            style: FilledButton.styleFrom(foregroundColor: kPrimary),
          ),
        ],
      ),
    );
  }
}

/* ============================================================
   Department browse — retained from the previous Courses screen.
   ============================================================ */

List<Widget> _programmePanels(College college) {
  final panels = <Widget>[];
  var panelIndex = 0;
  college.departmentsByCategory.forEach((category, departments) {
    panels.add(
      Padding(
        padding: const EdgeInsets.only(bottom: kSpaceSm, top: kSpaceXs),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: livelyGradient(
                  kBrandColors[panelIndex % kBrandColors.length],
                  shadeOf(kBrandColors[panelIndex % kBrandColors.length], 0.25),
                ),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: kBrandColors[panelIndex % kBrandColors.length].withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                category.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(width: kSpaceSm),
            Text(
              '${departments.length}',
              style: TextStyle(
                color: kTextSecondary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
    panels.add(
      ResponsiveGrid(
        items: [
          for (var i = 0; i < departments.length; i++)
            _DepartmentTile(
              department: departments[i],
              color: kBrandColors[(panelIndex + i) % kBrandColors.length],
            ),
        ],
      ),
    );
    panels.add(const SizedBox(height: kSpaceLg));
    panelIndex++;
  });
  return panels;
}

class _DepartmentTile extends StatelessWidget {
  final Department department;
  final Color color;
  const _DepartmentTile({required this.department, required this.color});

  @override
  Widget build(BuildContext context) {
    final isTwoYear = department.durationMonths <= 24;
    return BounceTap(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${department.name} (${department.code}) — ${department.durationLabel}',
            ),
            backgroundColor: color,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(kSpaceMd),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadiusMd)),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(kSpaceMd),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(kRadiusMd),
          border: Border.all(color: tintOf(color, 0.30)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: tintOf(color, 0.12),
                borderRadius: BorderRadius.circular(kRadiusSm),
              ),
              child: Center(
                child: Text(
                  department.code,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: kSpaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    department.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: kTextPrimary,
                    ),
                  ),
                  const SizedBox(height: kSpaceXs),
                  Row(
                    children: [
                      Icon(
                        isTwoYear ? Icons.timer_outlined : Icons.menu_book_rounded,
                        size: 13,
                        color: kTextSecondary,
                      ),
                      const SizedBox(width: kSpaceXs),
                      Text(
                        department.durationLabel,
                        style: TextStyle(fontSize: 12, color: kTextSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isTwoYear ? tintOf(kTextPrimary, 0.10) : tintOf(color, 0.10),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                department.durationBadge,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: isTwoYear ? kTextPrimary : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
