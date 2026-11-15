import 'attendance.dart';
import 'day.dart';
import 'team_day.dart';

/// How a group of people's day went: what each was marked as.
class StatusCounts {
  const StatusCounts({
    this.present = 0,
    this.absent = 0,
    this.halfDay = 0,
    this.leave = 0,
    this.lentOut = 0,
    this.pending = 0,
    this.late = 0,
  });

  final int present;

  /// Not counting people who were [lentOut].
  final int absent;
  final int halfDay;
  final int leave;

  /// Absent here because another team borrowed them for the day.
  final int lentOut;

  /// Not marked yet.
  final int pending;

  /// Came in late (present or half-day).
  final int late;

  int get total => present + absent + halfDay + leave + lentOut + pending;

  /// Everyone has a status. (Nobody on the list counts as done.)
  bool get done => pending == 0;

  /// One team's sheet for a day.
  factory StatusCounts.ofRows(Iterable<SheetRow> rows) {
    var counts = const StatusCounts();
    for (final row in rows) {
      counts = row.lentTo != null
          ? counts._plus(lentOut: 1)
          : counts._with(row.entry);
    }
    return counts;
  }

  /// The whole company for a day, counting each person once: someone on two
  /// teams' lists, or lent to another team, is counted by their best status
  /// (present, then half-day, leave, absent). [byTeam] is each team's rows.
  factory StatusCounts.ofCompany(Iterable<List<SheetRow>> byTeam) {
    final best = <String, AttendanceEntry?>{};
    for (final rows in byTeam) {
      for (final row in rows) {
        // Counted where they worked: that team has them as a guest.
        if (row.lentTo != null) continue;
        final entry = row.entry;
        if (!best.containsKey(row.empId) ||
            _rank(entry) > _rank(best[row.empId])) {
          best[row.empId] = entry;
        }
      }
    }
    var counts = const StatusCounts();
    for (final entry in best.values) {
      counts = counts._with(entry);
    }
    return counts;
  }

  /// Not marked ranks lowest.
  static int _rank(AttendanceEntry? entry) =>
      entry == null ? 0 : _statusRank(entry.status);

  StatusCounts _with(AttendanceEntry? entry) => switch (entry?.status) {
    null => _plus(pending: 1),
    AttendanceStatus.present => _plus(present: 1, late: entry!.late ? 1 : 0),
    AttendanceStatus.halfDay => _plus(halfDay: 1, late: entry!.late ? 1 : 0),
    AttendanceStatus.absent => _plus(absent: 1),
    AttendanceStatus.leave => _plus(leave: 1),
  };

  StatusCounts _plus({
    int present = 0,
    int absent = 0,
    int halfDay = 0,
    int leave = 0,
    int lentOut = 0,
    int pending = 0,
    int late = 0,
  }) => StatusCounts(
    present: this.present + present,
    absent: this.absent + absent,
    halfDay: this.halfDay + halfDay,
    leave: this.leave + leave,
    lentOut: this.lentOut + lentOut,
    pending: this.pending + pending,
    late: this.late + late,
  );
}

/// What one team recorded for an employee on one day.
class TeamEntry {
  const TeamEntry(this.teamId, this.entry);

  final String teamId;
  final AttendanceEntry entry;
}

/// One day of an employee's history: usually one team's entry, two if they
/// were on two teams' sheets.
class EmployeeDay {
  const EmployeeDay(this.date, this.entries);

  final Day date;
  final List<TeamEntry> entries;

  /// The day as it counts: the best status across teams.
  AttendanceStatus get status => entries
      .map((e) => e.entry.status)
      .reduce((a, b) => _statusRank(b) > _statusRank(a) ? b : a);

  bool get late => entries.any((e) => e.entry.late);

  /// Hours worked across teams, as far as both times are known.
  int get minutes => entries.fold(0, (sum, e) => sum + (e.entry.minutes ?? 0));
}

/// Which status counts when someone has two entries in a day.
int _statusRank(AttendanceStatus status) => switch (status) {
  AttendanceStatus.absent => 1,
  AttendanceStatus.leave => 2,
  AttendanceStatus.halfDay => 3,
  AttendanceStatus.present => 4,
};

/// [empId]'s recorded days in [sheets], newest first.
///
/// "Absent: working in another team" entries are left out: the team they
/// worked in has the real entry (and a stale one, where that team took them
/// off again, means nothing).
List<EmployeeDay> historyOf(String empId, Iterable<AttendanceSheet> sheets) {
  final byDate = <Day, List<TeamEntry>>{};
  for (final sheet in sheets) {
    final entry = sheet.entries[empId];
    if (entry == null || entry.workingIn != null) continue;
    (byDate[sheet.date] ??= []).add(TeamEntry(sheet.teamId, entry));
  }
  return [for (final e in byDate.entries) EmployeeDay(e.key, e.value)]
    ..sort((a, b) => b.date.compareTo(a.date));
}

/// Totals for an employee's [days] (one status per day).
class HistorySummary {
  HistorySummary(Iterable<EmployeeDay> days) {
    for (final day in days) {
      switch (day.status) {
        case AttendanceStatus.present:
          present++;
        case AttendanceStatus.absent:
          absent++;
        case AttendanceStatus.halfDay:
          halfDay++;
        case AttendanceStatus.leave:
          leave++;
      }
      if (day.late) late++;
      minutes += day.minutes;
    }
  }

  int present = 0;
  int absent = 0;
  int halfDay = 0;
  int leave = 0;
  int late = 0;
  int minutes = 0;
}
