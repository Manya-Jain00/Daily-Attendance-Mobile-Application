/// What a signed-in person is allowed to do.
enum UserRole {
  director,
  manager;

  static UserRole? tryParse(Object? value) {
    for (final role in values) {
      if (role.name == value) return role;
    }
    return null;
  }
}

/// A director or manager, as stored in `users/{phone}`.
///
/// The document is keyed by the person's mobile number (E.164, see
/// `PhoneNumber`), the same number Firebase puts in their login. So after
/// logging in the app can read it directly to find out which company the
/// person belongs to and what their role is, and a director can add a
/// manager before the manager has ever logged in.
class AppUser {
  const AppUser({
    required this.phone,
    required this.companyId,
    required this.role,
    required this.name,
    this.teamIds = const [],
    this.active = true,
  });

  /// Mobile number in E.164 form, e.g. `+919876543210`. Also the document id.
  final String phone;
  final String companyId;
  final UserRole role;
  final String name;

  /// Teams a manager looks after. Empty for a director, who sees every team.
  final List<String> teamIds;

  /// Deactivated users can still sign in to Firebase but are kept out of the
  /// app (and out of the data by the security rules).
  final bool active;

  /// Returns null when the document is missing a required field or has an
  /// unknown role, so a bad record can't crash the app.
  static AppUser? fromMap(String phone, Map<String, dynamic> data) {
    final companyId = data['companyId'];
    final role = UserRole.tryParse(data['role']);
    if (companyId is! String || companyId.isEmpty || role == null) return null;
    final teamIds = data['teamIds'];
    return AppUser(
      phone: phone,
      companyId: companyId,
      role: role,
      name: data['name'] as String? ?? '',
      teamIds: teamIds is List
          ? teamIds.whereType<String>().toList()
          : const [],
      active: data['active'] == true,
    );
  }
}
