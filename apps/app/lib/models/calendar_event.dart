import 'package:edtech_app/formats.dart';

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.courseId,
    required this.title,
    required this.kind,
    required this.startsAt,
    required this.endsAt,
    this.departmentId,
    this.assignmentId,
  });

  final String id;
  final String? courseId;
  final String? departmentId;
  final String title;
  final String kind;
  final DateTime startsAt;
  final DateTime? endsAt;

  /// Set when the event is an assignment's deadline. Such events follow the
  /// assignment and cannot be edited or deleted on their own.
  final String? assignmentId;

  bool get isAssignmentDeadline => assignmentId != null;

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id'] as String,
      courseId: json['courseId'] as String?,
      departmentId: json['departmentId'] as String?,
      title: json['title'] as String,
      kind: json['kind'] as String,
      startsAt: parseServerTime(json['startsAt']) ?? DateTime.now(),
      endsAt: parseServerTime(json['endsAt']),
      // Older APIs omit the key; both missing and null mean "not linked".
      assignmentId: json['assignmentId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'courseId': courseId,
      'departmentId': departmentId,
      'title': title,
      'kind': kind,
      'startsAt': startsAt.toUtc().toIso8601String(),
      'endsAt': endsAt?.toUtc().toIso8601String(),
      'assignmentId': assignmentId,
    };
  }
}
