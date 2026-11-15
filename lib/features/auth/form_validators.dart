import '../../core/manager_login.dart';

final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

String? validateEmail(String? value) {
  final email = (value ?? '').trim();
  if (email.isEmpty) return 'Enter your email';
  if (!_emailPattern.hasMatch(email)) return 'Enter a valid email address';
  return null;
}

/// Firebase requires at least 6 characters; we ask for 8.
String? validateNewPassword(String? value) {
  final password = value ?? '';
  if (password.isEmpty) return 'Choose a password';
  if (password.length < 8) return 'Use at least 8 characters';
  return null;
}

String? validateCompanyCode(String? value) {
  final code = ManagerLogin.normalizeCode(value ?? '');
  if (code.isEmpty) return 'Enter your company code';
  if (!ManagerLogin.isValidCode(code)) {
    return 'The code has ${ManagerLogin.codeLength} letters and numbers';
  }
  return null;
}

String? validateUsername(String? value) {
  final username = ManagerLogin.normalizeUsername(value ?? '');
  if (username.isEmpty) return 'Enter your username';
  if (!ManagerLogin.isValidUsername(username)) {
    return 'Use letters, numbers, dots or dashes';
  }
  return null;
}

/// For the CEO choosing a manager's username (the login screen uses
/// [validateUsername]).
String? validateNewUsername(String? value) {
  final username = ManagerLogin.normalizeUsername(value ?? '');
  if (username.isEmpty) return 'Choose a username';
  if (!ManagerLogin.isValidUsername(username)) {
    return 'Use 2 to 30 letters, numbers, dots, dashes or underscores, '
        'starting with a letter or number';
  }
  return null;
}

const maxPinLength = 12;

String? validateNewPin(String? value) {
  final pin = value ?? '';
  if (pin.isEmpty) return 'Choose a PIN';
  if (!RegExp(r'^\d+$').hasMatch(pin)) return 'Use digits only';
  if (pin.length < ManagerLogin.minPinLength) {
    return 'Use at least ${ManagerLogin.minPinLength} digits';
  }
  if (pin.length > maxPinLength) return 'Use at most $maxPinLength digits';
  return null;
}

/// A name for a person, team or company: required, at most 100 characters
/// (the security rules' limit).
String? Function(String?) validateName(String message) => (value) {
  final name = (value ?? '').trim();
  if (name.isEmpty) return message;
  if (name.length > 100) return 'Keep it under 100 characters';
  return null;
};

String? Function(String?) requiredField(String message) =>
    (value) => (value ?? '').trim().isEmpty ? message : null;
