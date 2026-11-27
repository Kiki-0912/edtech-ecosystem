import 'package:edtech_app/formats.dart';
import 'effort_score.dart';

class IntegrityReport {
  const IntegrityReport({
    required this.submissionId,
    required this.assignmentId,
    required this.studentId,
    required this.effortScore,
    required this.flags,
    required this.replayAvailable,
    required this.generatedAt,
  });

  final String? submissionId;
  final String assignmentId;
  final String studentId;
  final EffortScore effortScore;
  final List<String> flags;
  final bool replayAvailable;
  final DateTime generatedAt;

  factory IntegrityReport.fromJson(Map<String, dynamic> json) {
    return IntegrityReport(
      submissionId: json['submissionId'] as String?,
      assignmentId: json['assignmentId'] as String,
      studentId: json['studentId'] as String,
      effortScore:
          EffortScore.fromJson(json['effortScore'] as Map<String, dynamic>),
      flags: List<String>.from(json['flags'] as List<dynamic>),
      replayAvailable: json['replayAvailable'] as bool,
      generatedAt: parseServerTime(json['generatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'submissionId': submissionId,
      'assignmentId': assignmentId,
      'studentId': studentId,
      'effortScore': effortScore.toJson(),
      'flags': flags,
      'replayAvailable': replayAvailable,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
    };
  }
}
