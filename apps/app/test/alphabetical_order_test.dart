import 'dart:convert';

import 'package:edtech_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The API returns lists in insertion order; the app shows names A→Z so a
/// newly added entry appears in place instead of at the end.
void main() {
  final api = ApiService.instance;

  tearDown(() => api.httpClientOverride = null);

  void serve(Object data) {
    api.httpClientOverride = MockClient(
      (_) async => http.Response(jsonEncode({'data': data}), 200,
          headers: {'content-type': 'application/json'}),
    );
  }

  test('departments are sorted by name, case-insensitively', () async {
    serve([
      {'id': 'd1', 'name': 'Zoology', 'code': 'ZOO'},
      {'id': 'd2', 'name': 'architecture', 'code': 'ARC'},
      {'id': 'd3', 'name': 'Mechanical', 'code': 'MEC'},
    ]);
    final names = (await api.getDepartments()).map((d) => d['name']);
    expect(names, ['architecture', 'Mechanical', 'Zoology']);
  });

  test('students and department members are sorted by display name', () async {
    final rows = [
      {'id': 's1', 'displayName': 'Zara'},
      {'id': 's2', 'displayName': 'aeliya'},
      {'id': 's3', 'displayName': 'Bilal'},
    ];
    serve(rows);
    expect((await api.getStudents()).map((s) => s['displayName']),
        ['aeliya', 'Bilal', 'Zara']);
    serve(rows);
    expect(
        (await api.getStudentsByDepartment('d1')).map((s) => s['displayName']),
        ['aeliya', 'Bilal', 'Zara']);
  });
}
