import 'company.dart';
import 'day.dart';
import 'geo.dart';

/// How someone's day is recorded.
enum AttendanceStatus {
  present('Present', 'P'),
  absent('Absent', 'A'),
  halfDay('Half-day', 'H'),
  leave('Leave', 'L');

  const AttendanceStatus(this.label, this.letter);

  final String label;

  /// Short form, as on a paper register.
  final String letter;

  /// Present and half-day have in/out times; absent and leave don't.
  bool get worked => this == present || this == halfDay;

  static AttendanceStatus? tryParse(Object? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

/// `HH:MM` (24-hour) to minutes after midnight; null if it isn't a time.
int? minutesOf(String? time) {
  if (time == null || !CompanySettings.isValidTime(time)) return null;
  return int.parse(time.substring(0, 2)) * 60 + int.parse(time.substring(3));
}

/// Minutes after midnight to `HH:MM`.
String timeOf(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// `HH:MM` to "9:30 AM".
String displayTime(String time) {
  final minutes = minutesOf(time);
  if (minutes == null) return time;
  final h = minutes ~/ 60;
  final m = (minutes % 60).toString().padLeft(2, '0');
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  return '$hour12:$m ${h < 12 ? 'AM' : 'PM'}';
}

/// 495 to "8 h 15 m".
String displayDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m m';
  return m == 0 ? '$h h' : '$h h $m m';
}

/// Who saved an entry, when, and where their phone was. Kept on each entry,
/// so the director can see when every person was marked, not just when the
/// sheet was last saved.
class EntryStamp {
  const EntryStamp({
    required this.byPhone,
    this.byName = '',
    this.at,
    this.location,
  });

  /// Mobile number of whoever marked it.
  final String byPhone;

  /// Their name when they marked it (supervisors can't read each other's
  /// profiles, so it's kept here).
  final String byName;

  /// Server time it was saved. Null for a moment while the save is on its
  /// way.
  final DateTime? at;

  /// Where the phone was. Always there for a supervisor's entries; the
  /// director's corrections don't need one.
  final EntryLocation? location;

  static EntryStamp? fromMap(Map raw) {
    final by = raw['markedBy'];
    if (by is! String || by.isEmpty) return null;
    final at = raw['markedAt'];
    final name = raw['markedByName'];
    return EntryStamp(
      byPhone: by,
      byName: name is String ? name : '',
      at: at is DateTime ? at : null,
      location: EntryLocation.fromMap(raw['location']),
    );
  }
}

/// One employee's day in one team.
class AttendanceEntry {
  const AttendanceEntry._({
    required this.status,
    this.inTime,
    this.outTime,
    this.minutes,
    this.late = false,
    this.guest = false,
    this.workingIn,
    this.stamp,
  });

  /// Works out hours and the late flag from the times. Absent and leave have
  /// no times.
  factory AttendanceEntry.mark(
    AttendanceStatus status, {
    String? inTime,
    String? outTime,
    required CompanySettings settings,
    bool guest = false,
  }) {
    if (!status.worked) {
      return AttendanceEntry._(status: status, guest: guest);
    }
    final start = minutesOf(inTime);
    final end = minutesOf(outTime);
    return AttendanceEntry._(
      status: status,
      inTime: start == null ? null : inTime,
      outTime: end == null ? null : outTime,
      minutes: start != null && end != null && end > start ? end - start : null,
      late: start != null && start > minutesOf(settings.lateAfter)!,
      guest: guest,
    );
  }

  /// Absent from their own team because another team borrowed them for the
  /// day (they're present in [teamId]'s sheet).
  const AttendanceEntry.workingIn(String teamId)
    : this._(status: AttendanceStatus.absent, workingIn: teamId);

  final AttendanceStatus status;

  /// `HH:MM`, only when [status] is present or half-day.
  final String? inTime;
  final String? outTime;

  /// Time between in and out, once both are known.
  final int? minutes;

  /// Came in after the company's late cutoff.
  final bool late;

  /// Not on this team's monthly list: lent from another team for the day.
  final bool guest;

  /// Set when absent because they worked in this other team for the day.
  final String? workingIn;

  /// When and where it was saved, and by whom. Null for a new or changed
  /// entry that isn't saved yet: saving stamps it. Not part of [==], so an
  /// unchanged entry compares equal to its saved copy.
  final EntryStamp? stamp;

  /// Same status and times with the hours and late flag worked out again
  /// (e.g. after the director changed the late cutoff).
  AttendanceEntry recalculated(CompanySettings settings) {
    final entry = AttendanceEntry.mark(
      status,
      inTime: inTime,
      outTime: outTime,
      settings: settings,
      guest: guest,
    );
    return AttendanceEntry._(
      status: entry.status,
      inTime: entry.inTime,
      outTime: entry.outTime,
      minutes: entry.minutes,
      late: entry.late,
      guest: guest,
      stamp: stamp,
    );
  }

  /// The same entry with [stamp] (used once it's saved).
  AttendanceEntry withStamp(EntryStamp? stamp) => AttendanceEntry._(
    status: status,
    inTime: inTime,
    outTime: outTime,
    minutes: minutes,
    late: late,
    guest: guest,
    workingIn: workingIn,
    stamp: stamp,
  );

  /// Changes the times. A day shorter than the company's half-day hours
  /// becomes a half-day, and a longer one a full day.
  AttendanceEntry withTimes(
    String? inTime,
    String? outTime,
    CompanySettings settings,
  ) {
    var entry = AttendanceEntry.mark(
      status,
      inTime: inTime,
      outTime: outTime,
      settings: settings,
      guest: guest,
    );
    final minutes = entry.minutes;
    if (minutes != null) {
      final short = minutes < settings.halfDayBelowHours * 60;
      final wanted = short
          ? AttendanceStatus.halfDay
          : AttendanceStatus.present;
      if (wanted != entry.status) {
        entry = AttendanceEntry._(
          status: wanted,
          inTime: entry.inTime,
          outTime: entry.outTime,
          minutes: entry.minutes,
          late: entry.late,
          guest: guest,
        );
      }
    }
    return entry;
  }

  static AttendanceEntry? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final status = AttendanceStatus.tryParse(raw['status']);
    if (status == null) return null;
    String? text(String key) => raw[key] is String ? raw[key] as String : null;
    final minutes = raw['minutes'];
    return AttendanceEntry._(
      status: status,
      inTime: text('inTime'),
      outTime: text('outTime'),
      minutes: minutes is int ? minutes : null,
      late: raw['late'] == true,
      guest: raw['guest'] == true,
      workingIn: text('workingIn'),
      stamp: EntryStamp.fromMap(raw),
    );
  }

  /// The entry itself, without its [stamp] (the repository adds that).
  Map<String, Object> toMap() => {
    'status': status.name,
    'inTime': ?inTime,
    'outTime': ?outTime,
    'minutes': ?minutes,
    if (status.worked) 'late': late,
    if (guest) 'guest': true,
    'workingIn': ?workingIn,
  };

  @override
  bool operator ==(Object other) =>
      other is AttendanceEntry &&
      other.status == status &&
      other.inTime == inTime &&
      other.outTime == outTime &&
      other.minutes == minutes &&
      other.late == late &&
      other.guest == guest &&
      other.workingIn == workingIn;

  @override
  int get hashCode =>
      Object.hash(status, inTime, outTime, minutes, late, guest, workingIn);
}

/// A team's attendance for one day, as stored in
/// `companies/{companyId}/attendance/{teamId}_{yyyy-MM-dd}`. One document per
/// team per day, so a sheet is saved in one go and "done" is easy to see.
class AttendanceSheet {
  const AttendanceSheet({
    required this.teamId,
    required this.date,
    required this.entries,
    this.markedBy = '',
  });

  final String teamId;
  final Day date;

  /// Emp ID -> their day.
  final Map<String, AttendanceEntry> entries;

  /// Uid of whoever saved it last.
  final String markedBy;

  /// Most entries a sheet can hold (the security rules check the same).
  static const maxEntries = 600;

  static String docId(String teamId, Day date) => '${teamId}_${date.key}';

  static AttendanceSheet? fromMap(Map<String, dynamic> data) {
    final teamId = data['teamId'];
    final date = data['date'];
    final entries = data['entries'];
    if (teamId is! String || date is! String || entries is! Map) return null;
    final day = Day.tryParse(date);
    if (day == null) return null;
    return AttendanceSheet(
      teamId: teamId,
      date: day,
      entries: {
        for (final e in entries.entries)
          if (e.key is String)
            e.key as String: ?AttendanceEntry.fromMap(e.value),
      },
      markedBy: data['markedBy'] is String ? data['markedBy'] as String : '',
    );
  }
}

/// Every team's sheet for one day, to see who was lent to another team.
class DaySheets {
  DaySheets(Iterable<AttendanceSheet> sheets, this.date)
    : byTeam = {
        for (final s in sheets)
          if (s.date == date) s.teamId: s,
      };

  final Day date;
  final Map<String, AttendanceSheet> byTeam;

  /// The team (other than [teamId]) that borrowed [empId] for the day and
  /// marked them as working there, or null.
  String? lentTo(String empId, String teamId) {
    for (final sheet in byTeam.values) {
      if (sheet.teamId == teamId) continue;
      final entry = sheet.entries[empId];
      if (entry != null && entry.guest && entry.status.worked) {
        return sheet.teamId;
      }
    }
    return null;
  }
}

/// How far a team's sheet for a day has got.
class SheetProgress {
  const SheetProgress({required this.marked, required this.total});

  final int marked;
  final int total;

  /// Everyone on the sheet has a status. (An empty team has nothing to do.)
  bool get done => marked >= total;

  int get pending => total - marked;
}
