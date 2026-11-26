import 'package:flutter/foundation.dart';

import '../../core/models/app_user.dart';

/// Where the person using the app currently stands.
sealed class Session {
  const Session();
}

/// Still finding out whether someone is signed in, or loading their profile.
class SessionLoading extends Session {
  const SessionLoading();
}

class SignedOut extends Session {
  const SignedOut();
}

/// Logged in with a phone number that isn't in any company yet: either a
/// director setting up a new company, or a manager whose director hasn't
/// added this number.
class NeedsCompany extends Session {
  const NeedsCompany(this.phone);

  /// E.164, e.g. `+919876543210`.
  final String phone;
}

class SignedIn extends Session {
  const SignedIn(this.user);
  final AppUser user;
}

/// Signed in to Firebase, but can't use the app: a deactivated account, or
/// the profile couldn't be read.
class SessionProblem extends Session {
  const SessionProblem(this.message);
  final String message;
}

/// An SMS code on its way to [phone], to be passed to
/// [AuthService.confirmCode].
class CodeSent {
  const CodeSent({
    required this.phone,
    required this.verificationId,
    this.resendToken,
  });

  final String phone;
  final String verificationId;

  /// Lets Firebase resend to the same number without a new check.
  final int? resendToken;
}

/// Phone login, company set-up and sign-out. Notifies listeners whenever
/// [session] changes, which the router uses to send people to the right
/// screen.
///
/// Methods throw [AuthFailure] with a message that can be shown as is.
abstract class AuthService extends ChangeNotifier {
  Session get session;

  /// Texts a login code to [phone] (E.164). Pass the earlier [CodeSent] as
  /// [resend] to send it again.
  ///
  /// Returns null when the phone confirmed the number by itself (Android can
  /// read the SMS automatically); the person is then already logged in.
  Future<CodeSent?> sendCode(String phone, {CodeSent? resend});

  Future<void> confirmCode(CodeSent sent, String code);

  /// For [NeedsCompany]: creates a new company with the signed-in person as
  /// its director.
  Future<void> createCompany({
    required String name,
    required String companyName,
  });

  Future<void> signOut();
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
