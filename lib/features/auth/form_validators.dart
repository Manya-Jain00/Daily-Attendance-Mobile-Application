import '../../core/phone_number.dart';

String? validatePhone(String? value) {
  final phone = (value ?? '').trim();
  if (phone.isEmpty) return 'Enter the mobile number';
  if (!PhoneNumber.isValid(phone)) {
    return 'Enter a valid 10-digit mobile number';
  }
  return null;
}

String? validateSmsCode(String? value) {
  final code = (value ?? '').trim();
  if (code.isEmpty) return 'Enter the code from the SMS';
  if (!RegExp('^[0-9]{${PhoneNumber.codeLength}}\$').hasMatch(code)) {
    return 'The code has ${PhoneNumber.codeLength} digits';
  }
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
