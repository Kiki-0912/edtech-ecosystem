/// Date and time formatting helpers.
///
/// The app deliberately carries no `intl` dependency (it has to build as a
/// standalone offline APK), so these cover exactly the formats the screens
/// render: `Thu 11 Jun`, `09:00`, `2 h 10 min`.
const List<String> kWeekdayShort = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> kMonthShort = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `Thu 11 Jun`
String shortDate(DateTime date) =>
    '${kWeekdayShort[date.weekday - 1]} ${date.day} ${kMonthShort[date.month - 1]}';

/// `11 Jun`
String dayMonth(DateTime date) => '${date.day} ${kMonthShort[date.month - 1]}';

/// `09:00`
String clockTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

/// Single weekday initial used by the attendance day strip: `M T W T F S S`.
String weekdayInitial(DateTime date) => kWeekdayShort[date.weekday - 1][0];

/// `2 h 10 min`, `45 min`, `1 h`, `30 s`.
String durationLabel(int totalSeconds) {
  if (totalSeconds < 60) return '$totalSeconds s';
  final minutes = totalSeconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

/// True when both instants fall on the same calendar day in local time.
///
/// Both sides are converted with `toLocal()` so a UTC instant from the API
/// (`...Z`) is compared by the day the user actually sees.
bool isSameDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// Parses an API timestamp into local time, or `null` when absent/invalid.
///
/// The API sends UTC ISO strings (`2026-09-01T09:00:00.000Z`), which
/// `DateTime.parse` keeps in UTC; every screen formats wall-clock fields
/// (`hour`, `day`), so models convert to local here once.
DateTime? parseServerTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toLocal();
}

/// `4,210` — thousands separated for the metric rows.
String grouped(int value) => value.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
