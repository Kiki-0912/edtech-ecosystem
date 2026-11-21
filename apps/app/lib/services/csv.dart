/// Minimal RFC 4180 CSV helpers for spreadsheet import/export.
library;

/// Renders [rows] (maps keyed by [headers]) as CSV text with a header row.
String toCsv(List<String> headers, List<Map<String, dynamic>> rows) {
  String cell(Object? v) {
    final s = switch (v) {
      null => '',
      List() => v.join('; '),
      _ => v.toString(),
    };
    final needsQuotes =
        s.contains(RegExp(r'[",\r\n]')) || s.startsWith(' ') || s.endsWith(' ');
    return needsQuotes ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final buffer = StringBuffer()..writeln(headers.map(cell).join(','));
  for (final row in rows) {
    buffer.writeln(headers.map((h) => cell(row[h])).join(','));
  }
  return buffer.toString();
}

/// Parses CSV text into rows of fields. Handles quoted fields, escaped quotes
/// and CRLF/LF line endings. Blank lines are skipped.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;

  void endField() {
    row.add(field.toString().trim());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      endField();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

/// Parses CSV with a header row into maps keyed by header (case-insensitive
/// keys are normalised to the spellings in [aliases] when provided).
List<Map<String, String>> parseCsvRecords(
  String text, {
  Map<String, String> aliases = const {},
}) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return const [];
  String norm(String h) {
    final key = h.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    return aliases[key] ?? h.trim();
  }

  final headers = rows.first.map(norm).toList();
  return [
    for (final r in rows.skip(1))
      {
        for (var i = 0; i < headers.length; i++)
          headers[i]: i < r.length ? r[i] : '',
      },
  ];
}
