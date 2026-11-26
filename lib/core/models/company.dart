/// A firm, as stored in `companies/{companyId}`.
class Company {
  const Company({required this.name, required this.settings});

  final String name;

  final CompanySettings settings;

  factory Company.fromMap(Map<String, dynamic> data) => Company(
    name: data['name'] is String ? data['name'] as String : '',
    settings: CompanySettings.fromMap(data['settings']),
  );
}

/// Office rules the director sets in Settings. Times are 24-hour `HH:MM` strings,
/// which also sort correctly as text.
class CompanySettings {
  const CompanySettings({
    required this.officeStart,
    required this.officeEnd,
    required this.lateAfter,
    required this.halfDayBelowHours,
    required this.supervisorEditDays,
  });

  /// What every new company starts with.
  static const defaults = CompanySettings(
    officeStart: '09:30',
    officeEnd: '18:30',
    lateAfter: '09:45',
    halfDayBelowHours: 4,
    supervisorEditDays: 7,
  );

  /// Limits of the +/- buttons in Settings.
  static const maxHalfDayHours = 12;
  static const maxSupervisorEditDays = 31;

  static final _timePattern = RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$');

  static bool isValidTime(String value) => _timePattern.hasMatch(value);

  final String officeStart;
  final String officeEnd;

  /// Arriving after this time is marked late.
  final String lateAfter;

  /// Working fewer hours than this counts as a half day.
  final num halfDayBelowHours;

  /// How many past days a supervisor may still correct. Older records are
  /// director-only.
  final int supervisorEditDays;

  /// Reads stored settings, falling back to the default for any field that's
  /// missing or malformed, so a bad record can't crash the app.
  factory CompanySettings.fromMap(Object? raw) {
    final map = raw is Map ? raw : const {};
    String time(String key, String fallback) {
      final value = map[key];
      return value is String && isValidTime(value) ? value : fallback;
    }

    final halfDay = map['halfDayBelowHours'];
    final editDays = map['supervisorEditDays'];
    return CompanySettings(
      officeStart: time('officeStart', defaults.officeStart),
      officeEnd: time('officeEnd', defaults.officeEnd),
      lateAfter: time('lateAfter', defaults.lateAfter),
      halfDayBelowHours: halfDay is num ? halfDay : defaults.halfDayBelowHours,
      supervisorEditDays: editDays is int
          ? editDays
          : defaults.supervisorEditDays,
    );
  }

  Map<String, Object> toMap() => {
    'officeStart': officeStart,
    'officeEnd': officeEnd,
    'lateAfter': lateAfter,
    'halfDayBelowHours': halfDayBelowHours,
    'supervisorEditDays': supervisorEditDays,
  };

  CompanySettings copyWith({
    String? officeStart,
    String? officeEnd,
    String? lateAfter,
    num? halfDayBelowHours,
    int? supervisorEditDays,
  }) => CompanySettings(
    officeStart: officeStart ?? this.officeStart,
    officeEnd: officeEnd ?? this.officeEnd,
    lateAfter: lateAfter ?? this.lateAfter,
    halfDayBelowHours: halfDayBelowHours ?? this.halfDayBelowHours,
    supervisorEditDays: supervisorEditDays ?? this.supervisorEditDays,
  );

  @override
  bool operator ==(Object other) =>
      other is CompanySettings &&
      other.officeStart == officeStart &&
      other.officeEnd == officeEnd &&
      other.lateAfter == lateAfter &&
      other.halfDayBelowHours == halfDayBelowHours &&
      other.supervisorEditDays == supervisorEditDays;

  @override
  int get hashCode => Object.hash(
    officeStart,
    officeEnd,
    lateAfter,
    halfDayBelowHours,
    supervisorEditDays,
  );
}

/// A team, as stored in `companies/{companyId}/teams/{teamId}`.
///
/// Which supervisors look after a team is stored on each supervisor (`teamIds` in
/// their profile), not here, so the two can never disagree.
class Team {
  const Team({required this.id, required this.name});

  final String id;
  final String name;

  factory Team.fromMap(String id, Map<String, dynamic> data) =>
      Team(id: id, name: data['name'] is String ? data['name'] as String : '');
}
