import 'month.dart';

/// A calendar date, e.g. 15 November 2026. Stored as the text `2026-11-15`,
/// which also sorts correctly.
class Day implements Comparable<Day> {
  Day(int year, int month, int day) : _date = DateTime.utc(year, month, day);

  factory Day.of(DateTime date) => Day(date.year, date.month, date.day);

  /// Today on this phone.
  factory Day.today() => Day.of(DateTime.now());

  /// Midnight UTC, so adding days never trips over clock changes.
  final DateTime _date;

  int get year => _date.year;
  int get month => _date.month;
  int get day => _date.day;

  Month get monthOf => Month(year, month);

  static final _keyPattern = RegExp(
    r'^(\d{4})-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$',
  );

  /// Reads a key like `2026-11-15`; null if it isn't one.
  static Day? tryParse(String key) {
    final match = _keyPattern.firstMatch(key);
    if (match == null) return null;
    final result = Day(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
    // Rejects dates like 2026-02-30, which DateTime would roll over.
    return result.key == key ? result : null;
  }

  /// `2026-11-15`. (The security rules check the same format.)
  String get key =>
      '${year.toString().padLeft(4, '0')}-${_two(month)}-${_two(day)}';

  Day addDays(int days) => Day.of(_date.add(Duration(days: days)));

  Day get previous => addDays(-1);
  Day get next => addDays(1);

  /// Whole days from [other] to this day (negative if [other] is later).
  int daysSince(Day other) => _date.difference(other._date).inDays;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// "Sun, 15 Nov".
  String get label =>
      '${_weekdays[_date.weekday - 1]}, $day ${monthOf.name.substring(0, 3)}';

  /// "Sun, 15 Nov 2026".
  String get longLabel => '$label $year';

  @override
  int compareTo(Day other) => _date.compareTo(other._date);

  bool operator <(Day other) => compareTo(other) < 0;
  bool operator >(Day other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) => other is Day && other._date == _date;

  @override
  int get hashCode => _date.hashCode;

  @override
  String toString() => key;
}

String _two(int n) => n.toString().padLeft(2, '0');
