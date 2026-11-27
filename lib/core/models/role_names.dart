// Named parameters can't be private, so the constructor can't use
// initializing formals.
// ignore_for_file: prefer_initializing_formals

/// What one role is called in a company, e.g. "Supervisor" or a firm's own
/// "Foreman".
class RoleName {
  const RoleName(this.title, this._default);

  /// As typed in Settings, or the default ("Supervisor"). For headings,
  /// buttons and the start of a sentence.
  final String title;
  final String _default;

  static const maxLength = 30;

  bool get isDefault => title == _default;

  /// "Supervisors". Simple English rules; a firm's own word just gets an
  /// "s" unless it already ends in one.
  String get titles => pluralOf(title);

  /// For the middle of a sentence: "ask your director". A firm's own word
  /// is kept as typed ("ask your Seth-ji").
  String get word => isDefault ? title.toLowerCase() : title;
  String get words => isDefault ? titles.toLowerCase() : titles;

  /// "a supervisor", "an employee".
  String get aWord => '${_startsWithVowel(word) ? 'an' : 'a'} $word';

  static bool _startsWithVowel(String s) =>
      s.isNotEmpty && 'aeiouAEIOU'.contains(s[0]);

  static String pluralOf(String word) {
    if (word.isEmpty) return word;
    final lower = word.toLowerCase();
    if (lower.endsWith('s')) return word;
    // Foreman -> Foremen, Chairman -> Chairmen.
    if (lower.endsWith('man')) return '${word.substring(0, word.length - 2)}en';
    if (lower.endsWith('x') || lower.endsWith('ch') || lower.endsWith('sh')) {
      return '${word}es';
    }
    if (lower.length > 1 &&
        lower.endsWith('y') &&
        !'aeiou'.contains(lower[lower.length - 2])) {
      return '${word.substring(0, word.length - 1)}ies';
    }
    return '${word}s';
  }
}

/// What a company calls its roles. Director, Supervisor, Accountant and
/// Employee unless the director renames them in Settings. Only the names on
/// screen and in the Excel file change; the saved roles stay the same.
class RoleNames {
  const RoleNames({
    String director = defaultDirector,
    String supervisor = defaultSupervisor,
    String accountant = defaultAccountant,
    String employee = defaultEmployee,
  }) : _director = director,
       _supervisor = supervisor,
       _accountant = accountant,
       _employee = employee;

  final String _director;
  final String _supervisor;
  final String _accountant;
  final String _employee;

  static const defaultDirector = 'Director';
  static const defaultSupervisor = 'Supervisor';
  static const defaultAccountant = 'Accountant';
  static const defaultEmployee = 'Employee';

  static const defaults = RoleNames();

  /// Keys as stored in `settings.roleNames`.
  static const keys = ['director', 'supervisor', 'accountant', 'employee'];

  RoleName get director => RoleName(_director, defaultDirector);
  RoleName get supervisor => RoleName(_supervisor, defaultSupervisor);
  RoleName get accountant => RoleName(_accountant, defaultAccountant);
  RoleName get employee => RoleName(_employee, defaultEmployee);

  RoleName byKey(String key) => switch (key) {
    'director' => director,
    'supervisor' => supervisor,
    'accountant' => accountant,
    _ => employee,
  };

  static String defaultFor(String key) => switch (key) {
    'director' => defaultDirector,
    'supervisor' => defaultSupervisor,
    'accountant' => defaultAccountant,
    _ => defaultEmployee,
  };

  /// A name the security rules accept: 1 to 30 characters after trimming.
  static bool isValid(String name) {
    final t = name.trim();
    return t.isNotEmpty && t.length <= RoleName.maxLength;
  }

  /// [key] renamed to [name] (blank puts the default back).
  RoleNames rename(String key, String name) {
    final t = name.trim();
    final values = {for (final k in keys) k: byKey(k).title};
    values[key] = t.isEmpty ? defaultFor(key) : t;
    return RoleNames(
      director: values['director']!,
      supervisor: values['supervisor']!,
      accountant: values['accountant']!,
      employee: values['employee']!,
    );
  }

  /// Unknown, blank or too long names fall back to the default.
  factory RoleNames.fromMap(Object? raw) {
    final map = raw is Map ? raw : const {};
    String name(String key) {
      final v = map[key];
      return v is String && isValid(v) ? v.trim() : defaultFor(key);
    }

    return RoleNames(
      director: name('director'),
      supervisor: name('supervisor'),
      accountant: name('accountant'),
      employee: name('employee'),
    );
  }

  /// Only the renamed roles.
  Map<String, String> toMap() => {
    for (final k in keys)
      if (!byKey(k).isDefault) k: byKey(k).title,
  };

  bool get allDefault => toMap().isEmpty;

  @override
  bool operator ==(Object other) =>
      other is RoleNames &&
      other.director.title == director.title &&
      other.supervisor.title == supervisor.title &&
      other.accountant.title == accountant.title &&
      other.employee.title == employee.title;

  @override
  int get hashCode => Object.hash(
    director.title,
    supervisor.title,
    accountant.title,
    employee.title,
  );
}
