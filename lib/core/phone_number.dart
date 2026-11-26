/// Everyone logs in with their mobile number and a code sent to it by SMS.
///
/// Numbers are stored in international (E.164) form, e.g. `+919876543210`,
/// which is also what Firebase puts in the login token. A person's profile is
/// kept under that number (`users/{phone}`), so the director can add a
/// manager before the manager has ever logged in.
abstract final class PhoneNumber {
  /// Used when someone types a number without a country code.
  static const defaultCountryCode = '+91';

  /// Digits in a local Indian mobile number.
  static const localLength = 10;

  static const codeLength = 6; // Digits in the SMS code.

  static final _e164 = RegExp(r'^\+[1-9][0-9]{7,14}$');
  static final _indianMobile = RegExp(r'^\+91[6-9][0-9]{9}$');

  /// Turns what someone typed into E.164 form, or null if it isn't a usable
  /// mobile number. Spaces, dashes and brackets are ignored; a 10-digit
  /// number (or one starting with 0 or 91) is taken as Indian.
  static String? normalize(String input) {
    var digits = input.replaceAll(RegExp(r'[\s\-().]'), '');
    if (digits.startsWith('00')) digits = '+${digits.substring(2)}';
    if (!digits.startsWith('+')) {
      if (digits.length == localLength + 1 && digits.startsWith('0')) {
        digits = digits.substring(1);
      } else if (digits.length == localLength + 2 && digits.startsWith('91')) {
        digits = digits.substring(2);
      }
      if (digits.length != localLength) return null;
      digits = '$defaultCountryCode$digits';
    }
    if (!_e164.hasMatch(digits)) return null;
    if (digits.startsWith('+91') && !_indianMobile.hasMatch(digits)) {
      return null;
    }
    return digits;
  }

  static bool isValid(String input) => normalize(input) != null;

  /// For showing on screen: `+91 98765 43210`. Other countries are shown as
  /// stored.
  static String format(String e164) {
    if (_indianMobile.hasMatch(e164)) {
      return '+91 ${e164.substring(3, 8)} ${e164.substring(8)}';
    }
    return e164;
  }
}
