/// The firm's rule for how much of a day's pay ("Dihadi") a day's hours earn.
/// Salary is the sum over the days × the daily rate.
///
/// Hours are rounded to the nearest half hour (8 h 15 m counts as 8 h 30 m,
/// 8 h 14 m as 8 h). Whole hours go by [_byHour]; a half hour on top adds
/// [_halfHour]. Past 16 hours each hour adds 1/8 of a day.
library;

/// Dihadi for 0 to 16 whole hours, exactly as the firm gave it. 8 hours is a
/// full day; 3, 9, 11 and 15 hours earn the same as the hour beside them.
const _byHour = <double>[
  0, // 0 h
  0.125, // 1 h
  0.25, // 2 h
  0.5, // 3 h
  0.5, // 4 h
  0.625, // 5 h
  0.75, // 6 h
  0.875, // 7 h
  1, // 8 h
  1, // 9 h
  1.25, // 10 h
  1.25, // 11 h
  1.5, // 12 h
  1.625, // 13 h
  1.75, // 14 h
  1.75, // 15 h
  2, // 16 h
];

const _halfHour = 0.0625;
const _perHourAfterTable = 0.125;

/// Dihadi for [minutes] worked in a day.
double dayValue(int minutes) {
  if (minutes <= 0) return 0;
  // Nearest half hour; exactly a quarter past rounds up.
  final halfHours = (minutes + 15) ~/ 30;
  final hours = halfHours ~/ 2;
  final half = halfHours.isOdd ? _halfHour : 0.0;
  final last = _byHour.length - 1;
  final whole = hours <= last
      ? _byHour[hours]
      : _byHour[last] + (hours - last) * _perHourAfterTable;
  return whole + half;
}
