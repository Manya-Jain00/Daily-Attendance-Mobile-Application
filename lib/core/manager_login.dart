import 'dart:math';

/// Managers log in with company code + username + PIN instead of an email,
/// because many managers in small firms don't have one.
///
/// Firebase Authentication still needs an email, so each manager gets a
/// private, made-up address built from their code and username, under this
/// Firebase project's own domain. Nothing is ever sent to it.
abstract final class ManagerLogin {
  /// Letters and digits that can't be mixed up when read aloud or typed
  /// (no 0/O, 1/I/L).
  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const codeLength = 6;
  static const minPinLength = 6; // Firebase's minimum password length.

  static final _codePattern = RegExp('^[$_codeAlphabet]{$codeLength}\$');
  static final _usernamePattern = RegExp(r'^[a-z0-9][a-z0-9._-]{1,29}$');

  static const _emailDomain = 'login.daily-attendance-b1b1e.firebaseapp.com';

  static String newCompanyCode([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(
      codeLength,
      (_) => _codeAlphabet[r.nextInt(_codeAlphabet.length)],
    ).join();
  }

  static String normalizeCode(String code) =>
      code.replaceAll(RegExp(r'\s'), '').toUpperCase();

  static String normalizeUsername(String username) =>
      username.trim().toLowerCase();

  static bool isValidCode(String code) => _codePattern.hasMatch(code);

  static bool isValidUsername(String username) =>
      _usernamePattern.hasMatch(username);

  /// The hidden Firebase login address for a manager.
  static String email({
    required String companyCode,
    required String username,
  }) =>
      '${normalizeUsername(username)}'
      '@${normalizeCode(companyCode).toLowerCase()}.$_emailDomain';
}
