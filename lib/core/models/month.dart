/// A calendar month, e.g. November 2026. Stored as the text `2026-11`, which
/// also sorts correctly.
class Month implements Comparable<Month> {
  const Month(this.year, this.month) : assert(month >= 1 && month <= 12);

  factory Month.of(DateTime date) => Month(date.year, date.month);

  factory Month.now() => Month.of(DateTime.now());

  final int year;

  /// 1 (January) to 12 (December).
  final int month;

  static final _keyPattern = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$');

  /// Reads a key like `2026-11`; null if it isn't one.
  static Month? tryParse(String key) {
    final match = _keyPattern.firstMatch(key);
    if (match == null) return null;
    return Month(int.parse(match[1]!), int.parse(match[2]!));
  }

  /// `2026-11`. (The security rules check the same format.)
  String get key => '$year-${month.toString().padLeft(2, '0')}';

  Month get next => month == 12 ? Month(year + 1, 1) : Month(year, month + 1);

  Month get previous =>
      month == 1 ? Month(year - 1, 12) : Month(year, month - 1);

  Month minus(int months) {
    var result = this;
    for (var i = 0; i < months; i++) {
      result = result.previous;
    }
    return result;
  }

  static const _names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// "November 2026".
  String get label => '${_names[month - 1]} $year';

  /// "November".
  String get name => _names[month - 1];

  @override
  int compareTo(Month other) =>
      year != other.year ? year - other.year : month - other.month;

  bool operator <(Month other) => compareTo(other) < 0;
  bool operator >(Month other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is Month && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => key;
}
