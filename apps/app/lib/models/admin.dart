/// Models for the admin console (`/api/v1/admin/*`). Immutable, with
/// `fromJson` / `toJson` matching the API contract.
library;

import 'package:edtech_app/formats.dart';

DateTime _date(Object? value) =>
    parseServerTime(value) ?? DateTime.fromMillisecondsSinceEpoch(0);

List<String> _strings(Object? value) =>
    (value as List<dynamic>? ?? const []).map((e) => e.toString()).toList();

/// A user account as an admin sees it (never includes the password hash).
class AdminUser {
  const AdminUser({
    required this.id,
    required this.displayName,
    required this.email,
    required this.phone,
    required this.role,
    required this.isActive,
    required this.isPhoneVerified,
    required this.courseIds,
    required this.createdAt,
  });

  final String id;
  final String displayName;
  final String email;
  final String phone;

  /// `student`, `teacher` or `admin`.
  final String role;
  final bool isActive;
  final bool isPhoneVerified;
  final List<String> courseIds;
  final DateTime createdAt;

  bool get isStudent => role == 'student';
  bool get isTeacher => role == 'teacher';
  bool get isAdmin => role == 'admin';

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        role: json['role'] as String? ?? 'student',
        isActive: json['isActive'] as bool? ?? true,
        isPhoneVerified: json['isPhoneVerified'] as bool? ?? false,
        courseIds: _strings(json['courseIds']),
        createdAt: _date(json['createdAt']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'displayName': displayName,
        'email': email,
        'phone': phone,
        'role': role,
        'isActive': isActive,
        'isPhoneVerified': isPhoneVerified,
        'courseIds': courseIds,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

/// A course with its teacher and roster summary.
class AdminCourse {
  const AdminCourse({
    required this.id,
    required this.title,
    required this.code,
    required this.term,
    required this.teacherId,
    required this.teacherName,
    required this.studentIds,
    required this.studentCount,
    required this.assignmentCount,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String code;
  final String term;
  final String teacherId;
  final String teacherName;
  final List<String> studentIds;
  final int studentCount;
  final int assignmentCount;
  final DateTime createdAt;

  factory AdminCourse.fromJson(Map<String, dynamic> json) {
    final studentIds = _strings(json['studentIds']);
    return AdminCourse(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      code: json['code'] as String? ?? '',
      term: json['term'] as String? ?? '',
      teacherId: json['teacherId'] as String? ?? '',
      teacherName: json['teacherName'] as String? ?? '',
      studentIds: studentIds,
      studentCount:
          (json['studentCount'] as num?)?.toInt() ?? studentIds.length,
      assignmentCount: (json['assignmentCount'] as num?)?.toInt() ?? 0,
      createdAt: _date(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'code': code,
        'term': term,
        'teacherId': teacherId,
        'teacherName': teacherName,
        'studentIds': studentIds,
        'studentCount': studentCount,
        'assignmentCount': assignmentCount,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}

/// One student's effort score on one assignment.
class IntegrityRow {
  const IntegrityRow({
    required this.studentId,
    required this.studentName,
    required this.assignmentId,
    required this.assignmentTitle,
    required this.courseId,
    required this.courseTitle,
    required this.score,
    required this.flags,
    required this.computedAt,
  });

  final String studentId;
  final String studentName;
  final String assignmentId;
  final String assignmentTitle;
  final String courseId;
  final String courseTitle;

  /// Effort score, 0..100.
  final num score;

  /// Integrity flags; `none` means nothing was flagged.
  final List<String> flags;
  final DateTime computedAt;

  /// Same rule as the API's `?flagged=true`: any flag other than `none`.
  bool get isFlagged => flags.any((f) => f != 'none');

  factory IntegrityRow.fromJson(Map<String, dynamic> json) => IntegrityRow(
        studentId: json['studentId'] as String,
        studentName: json['studentName'] as String? ?? '',
        assignmentId: json['assignmentId'] as String,
        assignmentTitle: json['assignmentTitle'] as String? ?? '',
        courseId: json['courseId'] as String? ?? '',
        courseTitle: json['courseTitle'] as String? ?? '',
        score: json['score'] as num? ?? 0,
        flags: _strings(json['flags']),
        computedAt: _date(json['computedAt']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'studentId': studentId,
        'studentName': studentName,
        'assignmentId': assignmentId,
        'assignmentTitle': assignmentTitle,
        'courseId': courseId,
        'courseTitle': courseTitle,
        'score': score,
        'flags': flags,
        'computedAt': computedAt.toUtc().toIso8601String(),
      };
}

/// Record counts shown on the admin overview.
class AdminCounts {
  const AdminCounts({
    required this.students,
    required this.teachers,
    required this.admins,
    required this.inactiveUsers,
    required this.courses,
    required this.departments,
    required this.assignments,
    required this.submissions,
    required this.telemetryBatches,
    required this.flaggedReports,
  });

  final int students;
  final int teachers;
  final int admins;
  final int inactiveUsers;
  final int courses;
  final int departments;
  final int assignments;
  final int submissions;
  final int telemetryBatches;
  final int flaggedReports;

  factory AdminCounts.fromJson(Map<String, dynamic> json) {
    int n(String key) => (json[key] as num?)?.toInt() ?? 0;
    return AdminCounts(
      students: n('students'),
      teachers: n('teachers'),
      admins: n('admins'),
      inactiveUsers: n('inactiveUsers'),
      courses: n('courses'),
      departments: n('departments'),
      assignments: n('assignments'),
      submissions: n('submissions'),
      telemetryBatches: n('telemetryBatches'),
      flaggedReports: n('flaggedReports'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'students': students,
        'teachers': teachers,
        'admins': admins,
        'inactiveUsers': inactiveUsers,
        'courses': courses,
        'departments': departments,
        'assignments': assignments,
        'submissions': submissions,
        'telemetryBatches': telemetryBatches,
        'flaggedReports': flaggedReports,
      };
}

/// System status and counts from `GET /admin/overview`.
class AdminOverview {
  const AdminOverview({
    required this.counts,
    required this.storage,
    required this.database,
    required this.schemaVersion,
    required this.version,
    required this.serverTime,
  });

  final AdminCounts counts;

  /// `memory` or `postgres`.
  final String storage;

  /// `ok` or `unreachable`.
  final String database;

  /// Highest applied migration version (the in-memory store reports the
  /// latest migration too); null when the API cannot tell.
  final int? schemaVersion;
  final String version;
  final DateTime serverTime;

  bool get databaseOk => database == 'ok';

  factory AdminOverview.fromJson(Map<String, dynamic> json) => AdminOverview(
        counts: AdminCounts.fromJson(
          json['counts'] as Map<String, dynamic>? ?? const {},
        ),
        storage: json['storage'] as String? ?? 'memory',
        database: json['database'] as String? ?? 'unreachable',
        schemaVersion: (json['schemaVersion'] as num?)?.toInt(),
        version: json['version'] as String? ?? '',
        serverTime: _date(json['serverTime']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'counts': counts.toJson(),
        'storage': storage,
        'database': database,
        'schemaVersion': schemaVersion,
        'version': version,
        'serverTime': serverTime.toUtc().toIso8601String(),
      };
}
