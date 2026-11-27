import 'package:edtech_app/formats.dart';

class Course {
  const Course({
    required this.id,
    required this.title,
    required this.code,
    required this.teacherId,
    required this.studentIds,
    required this.term,
    required this.createdAt,
    this.teacherName,
    this.openAssignmentCount,
    int? studentCount,
  }) : _studentCount = studentCount;

  final String id;
  final String title;
  final String code;
  final String teacherId;
  final List<String> studentIds;
  final String term;
  final DateTime createdAt;

  /// Summary fields included by the /courses list endpoint.
  final String? teacherName;
  final int? openAssignmentCount;

  /// The API trims `studentIds` to the caller unless they teach or administer
  /// the course, so the enrolment size comes from `studentCount` when sent.
  final int? _studentCount;
  int get studentCount => _studentCount ?? studentIds.length;

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      id: json['id'] as String,
      title: json['title'] as String,
      code: json['code'] as String,
      teacherId: json['teacherId'] as String,
      studentIds: List<String>.from(json['studentIds'] as List<dynamic>),
      term: json['term'] as String,
      createdAt: parseServerTime(json['createdAt']) ?? DateTime.now(),
      teacherName: json['teacherName'] as String?,
      openAssignmentCount: json['openAssignmentCount'] as int?,
      studentCount: (json['studentCount'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'code': code,
      'teacherId': teacherId,
      'studentIds': studentIds,
      'term': term,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }
}
