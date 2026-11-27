import 'dart:convert';

import 'package:edtech_app/config.dart';
import 'package:edtech_app/models/admin.dart';
import 'package:edtech_app/models/assignment.dart';
import 'package:edtech_app/models/attendance.dart';
import 'package:edtech_app/models/attachment.dart';
import 'package:edtech_app/models/calendar_event.dart';
import 'package:edtech_app/models/channel.dart';
import 'package:edtech_app/models/chat_message.dart';
import 'package:edtech_app/models/college.dart';
import 'package:edtech_app/models/course.dart';
import 'package:edtech_app/models/effort_report.dart';
import 'package:edtech_app/models/submission.dart';
import 'package:edtech_app/services/offline_client.dart';
import 'package:http/http.dart' as http;

/// Non-2xx API response. [message] is the API's error message when available.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;

  /// The API's `UPPER_SNAKE` error code (e.g. `LAST_ADMIN`), when present.
  final String? code;

  @override
  String toString() => message;
}

/// Case-insensitive A→Z order for name lists, so new entries appear in place
/// instead of at the end (the API returns insertion order).
int _compareNames(String a, String b) {
  final byName = a.toLowerCase().compareTo(b.toLowerCase());
  return byName != 0 ? byName : a.compareTo(b);
}

List<Map<String, dynamic>> _sortedByName(List<Map<String, dynamic>> items) {
  String label(Map<String, dynamic> item) =>
      (item['displayName'] ?? item['name'] ?? item['code'] ?? '').toString();
  return items..sort((a, b) => _compareNames(label(a), label(b)));
}

class ApiService {
  ApiService._internal();
  static final ApiService instance = ApiService._internal();
  factory ApiService() => instance;

  /// Bearer token set by AuthProvider after login/signup/verify-sms/getMe.
  /// Included on every authenticated request.
  String? token;

  final http.Client _httpClient = http.Client();
  final http.Client _offlineClient = OfflineClient();

  /// Called when an authenticated request returns 401 (expired, revoked or
  /// disabled session) with the API's error. Wired to `AuthProvider.logout`
  /// by the app.
  void Function(ApiException error)? onUnauthorized;

  bool get isOffline => _offlineOverride ?? AppConfig.offlineMode;

  /// Optional test hook: force online/offline regardless of the build config.
  bool? _offlineOverride;
  set offlineMode(bool? value) => _offlineOverride = value;

  /// Optional test hook: when set, every request goes through this client
  /// (e.g. `package:http/testing` `MockClient`) instead of the network or the
  /// offline fake.
  http.Client? httpClientOverride;

  http.Client get _client =>
      httpClientOverride ??
      ((_offlineOverride ?? AppConfig.offlineMode)
          ? _offlineClient
          : _httpClient);

  /// [json] adds `Content-Type: application/json`. Pass false for requests
  /// without a body (DELETE): Fastify rejects an empty JSON body with 400.
  Map<String, String> _authHeaders({bool json = true}) {
    final headers = <String, String>{
      if (json) 'Content-Type': 'application/json',
    };
    if (token != null && token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /* ============================================
     COURSES
     ============================================ */
  // Read methods throw on failure (ApiException for API errors) so screens
  // show AsyncBody's error state; there is no built-in demo data to fall back
  // to. The offline build gets its demo data from OfflineClient instead.
  Future<List<Course>> getCourses() async {
    final response = await _client
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/api/v1/courses'),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    final List<dynamic> data =
        jsonDecode(response.body)['data'] as List<dynamic>;
    return data
        .map((item) => Course.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /* ============================================
     COLLEGES
     ============================================ */
  /// The college profile, or `null` when none is configured.
  Future<College?> getCollege() async {
    final response = await _client
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/api/v1/college'),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 404) {
      return null;
    }
    _throwOnError(response);
    final data = jsonDecode(response.body)['data'];
    return data is Map<String, dynamic> ? College.fromJson(data) : null;
  }

  /* ============================================
     ASSIGNMENTS
     ============================================ */
  Future<List<Assignment>> getAssignments(String courseId) async {
    final response = await _client
        .get(
          Uri.parse(
            '${AppConfig.apiBaseUrl}/api/v1/courses/$courseId/assignments',
          ),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    final List<dynamic> data =
        jsonDecode(response.body)['data'] as List<dynamic>;
    return data
        .map((item) => Assignment.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// `GET /assignments/:id` answers `{ data: { assignment, course } }`.
  Future<Assignment> getAssignment(String assignmentId) async {
    final response = await _client
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/api/v1/assignments/$assignmentId'),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    final data = jsonDecode(response.body)['data'] as Map<String, dynamic>;
    return Assignment.fromJson(data['assignment'] as Map<String, dynamic>);
  }

  /// Every enrolled student with their submission status. Staff only: the
  /// API answers 403 to students, which callers handle.
  Future<List<Map<String, dynamic>>> getRoster(String assignmentId) async {
    final response = await _client
        .get(
          Uri.parse(
            '${AppConfig.apiBaseUrl}/api/v1/assignments/$assignmentId/roster',
          ),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    return List<Map<String, dynamic>>.from(
      jsonDecode(response.body)['data']['roster'] as List<dynamic>,
    );
  }

  Future<Submission> submitAssignment({
    required String assignmentId,
    required String studentId,
    List<Attachment> attachments = const [],
  }) async {
    final response = await _client.post(
      Uri.parse(
        '${AppConfig.apiBaseUrl}/api/v1/assignments/$assignmentId/submissions',
      ),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{
        'studentId': studentId,
        'attachments': attachments.map((item) => item.toJson()).toList(),
      }),
    );
    _throwOnError(response);
    return Submission.fromJson(
      jsonDecode(response.body)['data'] as Map<String, dynamic>,
    );
  }

  /* ============================================
     STUDENTS
     ============================================ */

  Future<List<Map<String, dynamic>>> getStudents() async {
    final response = await _client
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/api/v1/students'),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    return _sortedByName(
      List<Map<String, dynamic>>.from(
        jsonDecode(response.body)['data'] as List<dynamic>,
      ),
    );
  }

  Future<Map<String, dynamic>> getStudent(String studentId) async {
    final response = await _client
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/api/v1/students/$studentId'),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createStudent({
    required String displayName,
    required String email,
    required String phone,
    String? courseId,
    String? departmentId,
  }) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/students'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{
        'displayName': displayName,
        'email': email,
        'phone': phone,
        if (courseId != null) 'courseId': courseId,
        if (departmentId != null) 'departmentId': departmentId,
      }),
    );
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateStudent({
    required String studentId,
    String? displayName,
    String? email,
    String? phone,
    String? courseId,
  }) async {
    final response = await _client.put(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/students/$studentId'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{
        if (displayName != null) 'displayName': displayName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (courseId != null) 'courseId': courseId,
      }),
    );
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<void> deleteStudent(String studentId) async {
    final response = await _client.delete(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/students/$studentId'),
      headers: _authHeaders(json: false),
    );
    _throwOnError(response);
  }

  Future<List<Map<String, dynamic>>> getStudentDepartments(
    String studentId,
  ) async {
    final response = await _client
        .get(
          Uri.parse(
            '${AppConfig.apiBaseUrl}/api/v1/students/$studentId/departments',
          ),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    return List<Map<String, dynamic>>.from(
      jsonDecode(response.body)['data'] as List<dynamic>,
    );
  }

  Future<Map<String, dynamic>> enrollStudentInDepartment({
    required String studentId,
    required String departmentId,
  }) async {
    final response = await _client.post(
      Uri.parse(
        '${AppConfig.apiBaseUrl}/api/v1/students/$studentId/departments',
      ),
      headers: _authHeaders(),
      body: jsonEncode(<String, String>{'departmentId': departmentId}),
    );
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<void> unenrollStudentFromDepartment({
    required String studentId,
    required String departmentId,
  }) async {
    final response = await _client.delete(
      Uri.parse(
        '${AppConfig.apiBaseUrl}/api/v1/students/$studentId/departments/$departmentId',
      ),
      headers: _authHeaders(json: false),
    );
    _throwOnError(response);
  }

  Future<List<Map<String, dynamic>>> getStudentsByCourse(
    String courseId,
  ) async {
    final response = await _client
        .get(
          Uri.parse(
            '${AppConfig.apiBaseUrl}/api/v1/courses/$courseId/students',
          ),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    return List<Map<String, dynamic>>.from(
      jsonDecode(response.body)['data'] as List<dynamic>,
    );
  }

  /* ============================================
     ATTENDANCE
     ============================================ */

  Future<List<AttendanceRecord>> getAttendanceRecords({
    String? courseId,
    String? date,
  }) async {
    final query = <String, String>{};
    if (courseId != null) query['courseId'] = courseId;
    if (date != null) query['date'] = date;
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/v1/attendance')
        .replace(queryParameters: query);
    final response = await _client
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    final List<dynamic> data =
        jsonDecode(response.body)['data'] as List<dynamic>;
    return data
        .map((item) => AttendanceRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AttendanceRecord> markAttendance({
    required String courseId,
    required String studentId,
    required String date,
    required String status,
    String? notes,
  }) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/attendance'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{
        'courseId': courseId,
        'studentId': studentId,
        'date': date,
        'status': status,
        if (notes != null) 'notes': notes,
      }),
    );
    _throwOnError(response);
    return AttendanceRecord.fromJson(
      jsonDecode(response.body)['data'] as Map<String, dynamic>,
    );
  }

  Future<List<AttendanceRecord>> bulkMarkAttendance({
    required String courseId,
    required String date,
    required List<Map<String, dynamic>> records,
  }) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/attendance/bulk'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{
        'courseId': courseId,
        'date': date,
        'records': records,
      }),
    );
    _throwOnError(response);
    final List<dynamic> data =
        jsonDecode(response.body)['data'] as List<dynamic>;
    return data
        .map((item) => AttendanceRecord.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Map<String, dynamic>>> getCourseStudentsWithAttendance({
    required String courseId,
    String? date,
  }) async {
    final query = <String, String>{};
    if (date != null) query['date'] = date;
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}/api/v1/attendance/course/$courseId/students',
    ).replace(queryParameters: query);
    final response = await _client
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    return List<Map<String, dynamic>>.from(
      jsonDecode(response.body)['data'] as List<dynamic>,
    );
  }

  /* ============================================
     TEACHER NOTES
     ============================================ */

  Future<List<TeacherNote>> getTeacherNotes({
    String? courseId,
    String? courseCode,
  }) async {
    final query = <String, String>{};
    if (courseId != null) query['courseId'] = courseId;
    if (courseCode != null) query['courseCode'] = courseCode;
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/v1/notes')
        .replace(queryParameters: query);
    final response = await _client
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    final List<dynamic> data =
        jsonDecode(response.body)['data'] as List<dynamic>;
    return data
        .map((item) => TeacherNote.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<TeacherNote> createTeacherNote({
    required String courseId,
    required String bookName,
    required String courseCode,
    required String title,
    required String content,
  }) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/notes'),
      headers: _authHeaders(),
      body: jsonEncode(<String, String>{
        'courseId': courseId,
        'bookName': bookName,
        'courseCode': courseCode,
        'title': title,
        'content': content,
      }),
    );
    _throwOnError(response);
    return TeacherNote.fromJson(
      jsonDecode(response.body)['data'] as Map<String, dynamic>,
    );
  }

  Future<TeacherNote> updateTeacherNote({
    required String id,
    String? bookName,
    String? courseCode,
    String? title,
    String? content,
  }) async {
    final response = await _client.put(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/notes/$id'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{
        if (bookName != null) 'bookName': bookName,
        if (courseCode != null) 'courseCode': courseCode,
        if (title != null) 'title': title,
        if (content != null) 'content': content,
      }),
    );
    _throwOnError(response);
    return TeacherNote.fromJson(
      jsonDecode(response.body)['data'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteTeacherNote(String id) async {
    final response = await _client.delete(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/notes/$id'),
      headers: _authHeaders(json: false),
    );
    _throwOnError(response);
  }

  /* ============================================
     DEPARTMENTS
     ============================================ */

  Future<List<Map<String, dynamic>>> getDepartments() async {
    final response = await _client
        .get(
          Uri.parse('${AppConfig.apiBaseUrl}/api/v1/departments'),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    return _sortedByName(
      List<Map<String, dynamic>>.from(
        jsonDecode(response.body)['data'] as List<dynamic>,
      ),
    );
  }

  Future<Map<String, dynamic>> createDepartment({
    required String name,
    required String code,
    required String category,
    required int durationMonths,
  }) async {
    final response = await _client
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}/api/v1/departments'),
          headers: _authHeaders(),
          body: jsonEncode({
            'name': name,
            'code': code,
            'category': category,
            'durationMonths': durationMonths,
          }),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateDepartment({
    required String id,
    String? name,
    String? code,
    String? category,
    int? durationMonths,
  }) async {
    final response = await _client
        .put(
          Uri.parse('${AppConfig.apiBaseUrl}/api/v1/departments/$id'),
          headers: _authHeaders(),
          body: jsonEncode({
            if (name != null) 'name': name,
            if (code != null) 'code': code,
            if (category != null) 'category': category,
            if (durationMonths != null) 'durationMonths': durationMonths,
          }),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<void> deleteDepartment(String id) async {
    final response = await _client
        .delete(
          Uri.parse('${AppConfig.apiBaseUrl}/api/v1/departments/$id'),
          headers: _authHeaders(json: false),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
  }

  Future<List<Map<String, dynamic>>> getStudentsByDepartment(
    String departmentId,
  ) async {
    final response = await _client
        .get(
          Uri.parse(
            '${AppConfig.apiBaseUrl}/api/v1/departments/$departmentId/students',
          ),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    return _sortedByName(
      List<Map<String, dynamic>>.from(
        jsonDecode(response.body)['data'] as List<dynamic>,
      ),
    );
  }

  /* ============================================
     EXCEL IMPORT/EXPORT
     ============================================ */

  Future<Map<String, dynamic>> importStudentsFromExcel({
    required String courseId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/excel/import/students'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{'courseId': courseId, 'rows': rows}),
    );
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> exportStudentsToExcel({String? courseId}) async {
    final query = <String, String>{};
    if (courseId != null) query['courseId'] = courseId;
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}/api/v1/excel/export/students',
    ).replace(queryParameters: query);
    final response = await _client
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> exportAttendanceToExcel({
    String? courseId,
    String? date,
  }) async {
    final query = <String, String>{};
    if (courseId != null) query['courseId'] = courseId;
    if (date != null) query['date'] = date;
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}/api/v1/excel/export/attendance',
    ).replace(queryParameters: query);
    final response = await _client
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> exportNotesToExcel({
    String? courseId,
    String? courseCode,
  }) async {
    final query = <String, String>{};
    if (courseId != null) query['courseId'] = courseId;
    if (courseCode != null) query['courseCode'] = courseCode;
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/v1/excel/export/notes')
        .replace(queryParameters: query);
    final response = await _client
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> postTelemetry(Map<String, dynamic> batch) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/telemetry/batches'),
      headers: _authHeaders(),
      body: jsonEncode(batch),
    );
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<IntegrityReport?> getIntegrityReportOrNull(
    String assignmentId,
    String studentId,
  ) async {
    final response = await _client
        .get(
          Uri.parse(
            '${AppConfig.apiBaseUrl}/api/v1/integrity/$assignmentId/$studentId',
          ),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 404) {
      return null;
    }
    _throwOnError(response);
    return IntegrityReport.fromJson(
      jsonDecode(response.body)['data'] as Map<String, dynamic>,
    );
  }

  Future<List<CalendarEvent>> getCalendar(
    String? userId, {
    String? departmentId,
  }) async {
    final query = <String, String>{};
    if (userId != null) query['userId'] = userId;
    if (departmentId != null) query['departmentId'] = departmentId;
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/v1/calendar')
        .replace(queryParameters: query.isEmpty ? null : query);
    final response = await _client
        .get(uri, headers: _authHeaders())
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    final List<dynamic> data =
        jsonDecode(response.body)['data'] as List<dynamic>;
    return data
        .map((item) => CalendarEvent.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<CalendarEvent> createCalendarEvent({
    required String title,
    required String kind,
    required DateTime startsAt,
    DateTime? endsAt,
    String? departmentId,
    String? courseId,
  }) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/calendar'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{
        'title': title,
        'kind': kind,
        // UTC with a `Z`, so the server stores an unambiguous instant.
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt?.toUtc().toIso8601String(),
        'departmentId': departmentId,
        'courseId': courseId,
      }),
    );
    _throwOnError(response);
    return CalendarEvent.fromJson(
      jsonDecode(response.body)['data'] as Map<String, dynamic>,
    );
  }

  Future<CalendarEvent> updateCalendarEvent({
    required String id,
    required String title,
    required String kind,
    required DateTime startsAt,
    DateTime? endsAt,
    String? departmentId,
    String? courseId,
  }) async {
    final response = await _client.put(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/calendar/$id'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{
        'title': title,
        'kind': kind,
        // UTC with a `Z`, so the server stores an unambiguous instant.
        'startsAt': startsAt.toUtc().toIso8601String(),
        'endsAt': endsAt?.toUtc().toIso8601String(),
        'departmentId': departmentId,
        // Omitted when null so an edit keeps the event's course (sending
        // null would detach it, and a teacher may not do that).
        if (courseId != null) 'courseId': courseId,
      }),
    );
    _throwOnError(response);
    return CalendarEvent.fromJson(
      jsonDecode(response.body)['data'] as Map<String, dynamic>,
    );
  }

  Future<void> deleteCalendarEvent(String id) async {
    final response = await _client.delete(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/calendar/$id'),
      headers: _authHeaders(json: false),
    );
    _throwOnError(response);
  }

  Future<List<ChatMessage>> getMessages(String channelId) async {
    final response = await _client
        .get(
          Uri.parse(
            '${AppConfig.apiBaseUrl}/api/v1/channels/$channelId/messages',
          ),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    final List<dynamic> data =
        jsonDecode(response.body)['data'] as List<dynamic>;
    return data
        .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> postMessage({
    required String channelId,
    required String authorId,
    required String body,
  }) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/channels/$channelId/messages'),
      headers: _authHeaders(),
      body: jsonEncode(<String, String>{'authorId': authorId, 'body': body}),
    );
    _throwOnError(response);
    return ChatMessage.fromJson(
      jsonDecode(response.body)['data'] as Map<String, dynamic>,
    );
  }

  Future<List<Channel>> getChannels(String courseId) async {
    final response = await _client
        .get(
          Uri.parse(
            '${AppConfig.apiBaseUrl}/api/v1/courses/$courseId/channels',
          ),
          headers: _authHeaders(),
        )
        .timeout(const Duration(seconds: 8));
    _throwOnError(response);
    final List<dynamic> data =
        jsonDecode(response.body)['data'] as List<dynamic>;
    return data
        .map((item) => Channel.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  /// Posts [body] to [courseId]'s discussion channel, preferring anything that
  /// is not an announcement channel. Returns the channel name on success so the
  /// caller can confirm where the message landed.
  Future<String> messageCourseChannel({
    required String courseId,
    required String authorId,
    required String body,
  }) async {
    final channels = await getChannels(courseId);
    if (channels.isEmpty) {
      throw Exception('This course has no chat channel yet');
    }
    final channel = channels.firstWhere(
      (item) => item.kind != 'announcement',
      orElse: () => channels.first,
    );
    await postMessage(channelId: channel.id, authorId: authorId, body: body);
    return channel.name;
  }

  /// Public sign-up. The API only creates student accounts here; teachers and
  /// admins are created through the admin console. [role] exists so tests can
  /// check that the API rejects anything else.
  Future<Map<String, dynamic>> register({
    required String phone,
    required String email,
    required String displayName,
    required String password,
    String role = 'student',
  }) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/auth/register'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{
        'phone': phone,
        'email': email,
        'display_name': displayName,
        'password': password,
        'role': role,
      }),
    );
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  /// Signs in with a phone number or an email address (the API accepts either).
  Future<Map<String, dynamic>> login({
    String? phone,
    String? email,
    required String password,
  }) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/auth/login'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        'password': password,
      }),
    );
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendSmsCode({required String phone}) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/auth/send-sms'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{'phone': phone}),
    );
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifySmsCode({
    required String phone,
    required String code,
  }) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/auth/verify-sms'),
      headers: _authHeaders(),
      body: jsonEncode(<String, dynamic>{'phone': phone, 'code': code}),
    );
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getMe({required String token}) async {
    final response = await _client.get(
      Uri.parse('${AppConfig.apiBaseUrl}/api/v1/auth/me'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    _throwOnError(response);
    return jsonDecode(response.body)['data'] as Map<String, dynamic>;
  }

  void _throwOnError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    // Surface the API's `{ error: { code, message } }` envelope when present.
    String message = 'Request failed (${response.statusCode})';
    String? code;
    try {
      final body = jsonDecode(response.body);
      final error = body is Map ? body['error'] : null;
      final apiMessage = error is Map ? error['message'] : null;
      final apiCode = error is Map ? error['code'] : null;
      if (apiMessage is String && apiMessage.isNotEmpty) message = apiMessage;
      if (apiCode is String && apiCode.isNotEmpty) code = apiCode;
    } catch (_) {
      // Non-JSON body: keep the generic message.
    }
    final error = ApiException(response.statusCode, message, code: code);
    if (response.statusCode == 401 &&
        !(response.request?.url.path ?? '').contains('/auth/')) {
      onUnauthorized?.call(error);
    }
    throw error;
  }

  /* ============================================
     ADMIN (/api/v1/admin, admin role only)
     Every method rethrows ApiException: the console must never show demo
     data in place of the real state.
     ============================================ */

  Future<Object?> _admin(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/api/v1/admin$path')
        .replace(queryParameters: (query?.isEmpty ?? true) ? null : query);
    final request = http.Request(method, uri)
      ..headers.addAll(_authHeaders(json: body != null));
    if (body != null) request.body = jsonEncode(body);
    final streamed =
        await _client.send(request).timeout(const Duration(seconds: 15));
    final response = await http.Response.fromStream(streamed);
    _throwOnError(response);
    return (jsonDecode(response.body) as Map<String, dynamic>)['data'];
  }

  List<Map<String, dynamic>> _rows(Object? data) =>
      List<Map<String, dynamic>>.from(data as List<dynamic>);

  /// `status` is `active`, `inactive` or `all`; [query] matches name, email
  /// or phone.
  Future<List<AdminUser>> adminListUsers({
    String? role,
    String? query,
    String status = 'all',
  }) async {
    final data = await _admin(
      'GET',
      '/users',
      query: {
        if (role != null) 'role': role,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'status': status,
      },
    );
    return _rows(data).map(AdminUser.fromJson).toList();
  }

  Future<AdminUser> adminCreateUser({
    required String displayName,
    String? email,
    String? phone,
    required String role,
    required String password,
  }) async {
    final data = await _admin(
      'POST',
      '/users',
      body: {
        'displayName': displayName,
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'role': role,
        'password': password,
      },
    );
    return AdminUser.fromJson(data as Map<String, dynamic>);
  }

  /// Only the given fields are sent; `null` means "leave unchanged".
  Future<AdminUser> adminUpdateUser(
    String id, {
    String? displayName,
    String? email,
    String? phone,
    String? role,
    bool? isActive,
  }) async {
    final data = await _admin(
      'PATCH',
      '/users/$id',
      body: {
        if (displayName != null) 'displayName': displayName,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (role != null) 'role': role,
        if (isActive != null) 'isActive': isActive,
      },
    );
    return AdminUser.fromJson(data as Map<String, dynamic>);
  }

  Future<void> adminResetPassword(String id, String password) async {
    await _admin('POST', '/users/$id/password', body: {'password': password});
  }

  Future<void> adminDeleteUser(String id) async {
    await _admin('DELETE', '/users/$id');
  }

  Future<List<AdminCourse>> adminListCourses() async {
    final data = await _admin('GET', '/courses');
    return _rows(data).map(AdminCourse.fromJson).toList();
  }

  Future<AdminCourse> adminCreateCourse({
    required String title,
    required String code,
    required String term,
    required String teacherId,
  }) async {
    final data = await _admin(
      'POST',
      '/courses',
      body: {
        'title': title,
        'code': code,
        'term': term,
        'teacherId': teacherId,
      },
    );
    return AdminCourse.fromJson(data as Map<String, dynamic>);
  }

  Future<AdminCourse> adminUpdateCourse(
    String id, {
    String? title,
    String? code,
    String? term,
    String? teacherId,
  }) async {
    final data = await _admin(
      'PATCH',
      '/courses/$id',
      body: {
        if (title != null) 'title': title,
        if (code != null) 'code': code,
        if (term != null) 'term': term,
        if (teacherId != null) 'teacherId': teacherId,
      },
    );
    return AdminCourse.fromJson(data as Map<String, dynamic>);
  }

  Future<void> adminDeleteCourse(String id) async {
    await _admin('DELETE', '/courses/$id');
  }

  /// Replaces the course roster with exactly [studentIds].
  Future<AdminCourse> adminSetCourseStudents(
    String id,
    List<String> studentIds,
  ) async {
    final data = await _admin(
      'PUT',
      '/courses/$id/students',
      body: {'studentIds': studentIds},
    );
    return AdminCourse.fromJson(data as Map<String, dynamic>);
  }

  Future<List<IntegrityRow>> adminIntegrity({bool flaggedOnly = false}) async {
    final data = await _admin(
      'GET',
      '/integrity',
      query: {'flagged': flaggedOnly ? 'true' : 'false'},
    );
    return _rows(data).map(IntegrityRow.fromJson).toList();
  }

  Future<AdminOverview> adminOverview() async {
    final data = await _admin('GET', '/overview');
    return AdminOverview.fromJson(data as Map<String, dynamic>);
  }
}
