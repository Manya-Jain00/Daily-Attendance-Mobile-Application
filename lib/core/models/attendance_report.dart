import 'attendance.dart';
import 'day.dart';
import 'day_value.dart';
import 'employee.dart';
import 'month.dart';
import 'overview.dart';
import 'roster.dart';

/// The dates a report covers, both included.
class ReportPeriod {
  ReportPeriod(this.from, this.to) : assert(!(to < from));

  /// A whole calendar month.
  factory ReportPeriod.month(Month month) => ReportPeriod(
    Day(month.year, month.month, 1),
    Day(month.next.year, month.next.month, 1).previous,
  );

  final Day from;
  final Day to;

  /// The month, when the period is exactly one whole month.
  Month? get month {
    final m = from.monthOf;
    final whole = ReportPeriod.month(m);
    return whole.from == from && whole.to == to ? m : null;
  }

  int get days => to.daysSince(from) + 1;

  /// Every month the period touches, oldest first.
  List<Month> get months => [
    for (var m = from.monthOf; !(m > to.monthOf); m = m.next) m,
  ];

  /// "November 2026", or "1 Nov 2026 – 15 Nov 2026".
  String get label =>
      month?.label ??
      (from == to ? shortDate(from) : '${shortDate(from)} – ${shortDate(to)}');

  /// For file names: `2026-11` or `2026-11-01_2026-11-15`.
  String get key => month?.key ?? '${from.key}_${to.key}';

  bool contains(Day day) => !(day < from) && !(day > to);

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// "1 Nov 2026".
String shortDate(Day d) =>
    '${d.day} ${d.monthOf.name.substring(0, 3)} ${d.year}';

/// "16-10-2026", as on the firm's sheets.
String sheetDate(Day d) =>
    '${d.day.toString().padLeft(2, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.year}';

/// "08:20" (hours and minutes worked), as on the firm's sheets.
String hoursAndMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// One day of an employee's report.
class ReportDay {
  ReportDay(this.day);

  final EmployeeDay day;

  Day get date => day.date;
  AttendanceStatus get status => day.status;
  bool get late => day.late;

  /// Hours worked, as far as both times are known.
  int get minutes => day.minutes;

  /// Worked, but an in or out time is missing, so the hours are short.
  bool get timeMissing =>
      day.entries.any((e) => e.entry.status.worked && e.entry.minutes == null);

  /// Earliest in-time and latest out-time across teams (`HH:MM`).
  String? get inTime => _pick([
    for (final e in day.entries) ?e.entry.inTime,
  ], (a, b) => a.compareTo(b) < 0);
  String? get outTime => _pick([
    for (final e in day.entries) ?e.entry.outTime,
  ], (a, b) => a.compareTo(b) > 0);

  /// Share of a day's pay the hours earn (absent and leave earn nothing).
  double get dihadi => status.worked ? dayValue(minutes) : 0;

  static String? _pick(List<String> times, bool Function(String, String) wins) {
    String? best;
    for (final t in times) {
      if (best == null || wins(t, best)) best = t;
    }
    return best;
  }
}

/// One employee over the period.
class ReportRow {
  ReportRow({
    required this.employee,
    required this.teamIds,
    required List<EmployeeDay> days,
  }) : summary = HistorySummary(days),
       days = [for (final d in days.reversed) ReportDay(d)]
         ..sort((a, b) => a.date.compareTo(b.date));

  final Employee employee;

  /// Teams whose list they were on, then any other team that marked them
  /// (e.g. lent for a day).
  final List<String> teamIds;

  final HistorySummary summary;

  /// Days any team marked them, oldest first.
  final List<ReportDay> days;

  int get daysRecorded => days.length;

  /// Sum of each day's share of pay.
  double get dihadi => days.fold(0, (sum, d) => sum + d.dihadi);

  /// Days worked with an in or out time missing.
  int get timesMissing => days.where((d) => d.timeMissing).length;
}

/// Every employee's attendance and Dihadi over a [period].
///
/// Lists everyone a team marked in the period, and every active employee on
/// a team's list in one of its months even if nothing was marked (so nobody
/// is missed).
class AttendanceReport {
  factory AttendanceReport({
    required ReportPeriod period,
    required Iterable<Employee> employees,
    required Iterable<Roster> rosters,
    required Iterable<String> teamIds,
    required Iterable<AttendanceSheet> sheets,
  }) {
    final inPeriod = [
      for (final s in sheets)
        if (period.contains(s.date)) s,
    ];
    final byId = {for (final e in employees) e.empId: e};

    // Emp ID -> teams, in order: list teams first, then teams that marked them.
    final teamsOf = <String, Set<String>>{};
    for (final month in period.months) {
      for (final teamId in teamIds) {
        for (final empId in EffectiveRoster.of(rosters, teamId, month).empIds) {
          if (byId[empId]?.active ?? false) {
            (teamsOf[empId] ??= <String>{}).add(teamId);
          }
        }
      }
    }
    final sorted = [...inPeriod]..sort((a, b) => a.date.compareTo(b.date));
    for (final sheet in sorted) {
      sheet.entries.forEach((empId, entry) {
        if (entry.workingIn != null) return;
        (teamsOf[empId] ??= <String>{}).add(sheet.teamId);
      });
    }

    final rows = [
      for (final MapEntry(key: empId, value: teams) in teamsOf.entries)
        ReportRow(
          // Employees are never deleted, but a bad record shouldn't drop a day.
          employee: byId[empId] ?? Employee(empId: empId, name: '(Unknown)'),
          teamIds: teams.toList(),
          days: historyOf(empId, inPeriod),
        ),
    ]..sort((a, b) => Employee.compareByEmpId(a.employee, b.employee));
    return AttendanceReport._(period, rows);
  }

  AttendanceReport._(this.period, this.rows);

  final ReportPeriod period;

  /// Sorted by Emp ID.
  final List<ReportRow> rows;

  double get dihadi => rows.fold(0, (sum, r) => sum + r.dihadi);

  /// `attendance-2026-11.xlsx`.
  String get fileName => 'attendance-${period.key}.xlsx';
}
