/// What a signed-in person is allowed to do.
enum UserRole {
  ceo,
  manager;

  static UserRole? tryParse(Object? value) {
    for (final role in values) {
      if (role.name == value) return role;
    }
    return null;
  }
}

/// A CEO or manager, as stored in `users/{uid}`.
///
/// The document is keyed by the Firebase Auth uid, so after login the app can
/// read it directly to find out which company the person belongs to and what
/// their role is.
class AppUser {
  const AppUser({
    required this.uid,
    required this.companyId,
    required this.role,
    required this.name,
    required this.email,
    this.companyCode = '',
    this.username = '',
    this.teamIds = const [],
    this.active = true,
  });

  final String uid;
  final String companyId;
  final UserRole role;
  final String name;
  final String email;

  /// The company's login code, which managers type when logging in.
  final String companyCode;

  /// A manager's login name within the company. Empty for a CEO, who logs in
  /// with their email.
  final String username;

  /// Teams a manager looks after. Empty for a CEO, who sees every team.
  final List<String> teamIds;

  /// Deactivated users can still sign in to Firebase but are kept out of the
  /// app (and out of the data by the security rules).
  final bool active;

  /// Returns null when the document is missing a required field or has an
  /// unknown role, so a bad record can't crash the app.
  static AppUser? fromMap(String uid, Map<String, dynamic> data) {
    final companyId = data['companyId'];
    final role = UserRole.tryParse(data['role']);
    if (companyId is! String || companyId.isEmpty || role == null) return null;
    final teamIds = data['teamIds'];
    return AppUser(
      uid: uid,
      companyId: companyId,
      role: role,
      name: data['name'] as String? ?? '',
      email: data['email'] as String? ?? '',
      companyCode: data['companyCode'] as String? ?? '',
      username: data['username'] as String? ?? '',
      teamIds: teamIds is List
          ? teamIds.whereType<String>().toList()
          : const [],
      active: data['active'] == true,
    );
  }
}
