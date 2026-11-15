import 'month.dart';

/// Who works in a team for one month, as stored in
/// `companies/{companyId}/rosters/{teamId}_{yyyy-MM}`.
///
/// The daily attendance sheet lists these people every day of the month, so
/// the manager doesn't pick the team again each day.
class Roster {
  const Roster({
    required this.teamId,
    required this.month,
    required this.empIds,
  });

  final String teamId;
  final Month month;
  final List<String> empIds;

  /// Most people a team's list can hold (the security rules check the same).
  static const maxPeople = 500;

  static String docId(String teamId, Month month) => '${teamId}_${month.key}';

  static Roster? fromMap(Map<String, dynamic> data) {
    final teamId = data['teamId'];
    final month = data['month'];
    final empIds = data['empIds'];
    if (teamId is! String || month is! String || empIds is! List) return null;
    final parsed = Month.tryParse(month);
    if (parsed == null) return null;
    return Roster(
      teamId: teamId,
      month: parsed,
      empIds: empIds.whereType<String>().toList(),
    );
  }
}

/// A team's list for a month as it applies: the month's own list if one was
/// saved, otherwise a copy of the latest earlier month's.
class EffectiveRoster {
  const EffectiveRoster({required this.empIds, this.copiedFrom});

  final List<String> empIds;

  /// The earlier month the list comes from, or null when this month has its
  /// own saved list (or nothing at all was ever saved).
  final Month? copiedFrom;

  bool get isCopy => copiedFrom != null;

  /// Works out [teamId]'s list for [month] from [rosters] (any teams, any
  /// months).
  factory EffectiveRoster.of(
    Iterable<Roster> rosters,
    String teamId,
    Month month,
  ) {
    Roster? best;
    for (final r in rosters) {
      if (r.teamId != teamId || r.month > month) continue;
      if (best == null || r.month > best.month) best = r;
    }
    if (best == null) return const EffectiveRoster(empIds: []);
    return EffectiveRoster(
      empIds: best.empIds,
      copiedFrom: best.month == month ? null : best.month,
    );
  }
}
