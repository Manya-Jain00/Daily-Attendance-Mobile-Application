import 'attendance.dart';
import 'day.dart';
import 'employee.dart';
import 'roster.dart';

/// One line of a team's sheet for a day.
class SheetRow {
  const SheetRow({
    required this.empId,
    required this.employee,
    required this.entry,
    this.lentTo,
    this.guest = false,
  });

  final String empId;

  /// Null if the employee record is missing (shown by Emp ID only).
  final Employee? employee;

  /// What's recorded, or null if not marked yet. A stale "working in another
  /// team" entry (that team no longer has them) counts as not marked.
  final AttendanceEntry? entry;

  /// Another team borrowed them for the day, so they're absent here and
  /// can't be marked.
  final String? lentTo;

  /// Borrowed from another team for the day (not on this team's list).
  final bool guest;

  String get name => employee?.name ?? empId;

  bool get marked => lentTo != null || entry != null;
}

/// Who is on [teamId]'s sheet for a day, and what they're marked as.
///
/// That's the team's monthly list ([listEmpIds]) plus anyone borrowed for the
/// day. People who have left are kept off, unless they already have an entry
/// that day. [entries] is the sheet as saved, or the supervisor's unsaved
/// changes.
List<SheetRow> sheetRows({
  required String teamId,
  required List<String> listEmpIds,
  required Map<String, AttendanceEntry> entries,
  required Map<String, Employee> employees,
  required DaySheets day,
}) {
  final rows = <SheetRow>[];
  final seen = <String>{};
  for (final id in listEmpIds) {
    if (!seen.add(id)) continue;
    final employee = employees[id];
    var entry = entries[id];
    final active = employee?.active ?? false;
    if (!active && entry == null) continue;
    final lentTo = day.lentTo(id, teamId);
    if (lentTo == null && entry?.workingIn != null) entry = null;
    rows.add(
      SheetRow(
        empId: id,
        employee: employee,
        entry: lentTo == null ? entry : AttendanceEntry.workingIn(lentTo),
        lentTo: lentTo,
      ),
    );
  }
  rows.sort((a, b) => compareNatural(a.empId, b.empId));
  final guests = [
    for (final e in entries.entries)
      if (e.value.guest && !seen.contains(e.key))
        SheetRow(
          empId: e.key,
          employee: employees[e.key],
          entry: e.value,
          guest: true,
        ),
  ]..sort((a, b) => compareNatural(a.empId, b.empId));
  return [...rows, ...guests];
}

SheetProgress progressOf(List<SheetRow> rows) => SheetProgress(
  marked: rows.where((r) => r.marked).length,
  total: rows.length,
);

/// The entries to save for [rows]: everyone marked, with people lent to
/// another team saved as absent there.
Map<String, AttendanceEntry> entriesToSave(List<SheetRow> rows) => {
  for (final r in rows) r.empId: ?r.entry,
};

/// Everything needed to draw any team's sheet for one day.
class DayData {
  DayData({
    required this.date,
    required List<AttendanceSheet> sheets,
    required this.rosters,
    required List<Employee> employees,
  }) : day = DaySheets(sheets, date),
       employees = {for (final e in employees) e.empId: e};

  final Day date;
  final DaySheets day;

  /// Saved monthly lists covering [date]'s month (see [EffectiveRoster]).
  final List<Roster> rosters;
  final Map<String, Employee> employees;

  /// Who's on [teamId]'s monthly list for [date].
  List<String> listOf(String teamId) =>
      EffectiveRoster.of(rosters, teamId, date.monthOf).empIds;

  /// The saved entries, or [draft] (unsaved changes) when given.
  List<SheetRow> rows(String teamId, [Map<String, AttendanceEntry>? draft]) =>
      sheetRows(
        teamId: teamId,
        listEmpIds: listOf(teamId),
        entries: draft ?? day.byTeam[teamId]?.entries ?? const {},
        employees: employees,
        day: day,
      );

  SheetProgress progress(String teamId) => progressOf(rows(teamId));
}
