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

class SignedIn extends Session {
  const SignedIn(this.user);
  final AppUser user;
}

/// Signed in to Firebase, but can't use the app: no profile, a deactivated
/// account, or the profile couldn't be read.
class SessionProblem extends Session {
  const SessionProblem(this.message);
  final String message;
}

/// Login, sign-up and sign-out. Notifies listeners whenever [session] changes,
/// which the router uses to send people to the right screen.
///
/// Methods throw [AuthFailure] with a message that can be shown as is.
abstract class AuthService extends ChangeNotifier {
  Session get session;

  /// CEO login.
  Future<void> signIn({required String email, required String password});

  /// Manager login, with no email needed.
  Future<void> signInManager({
    required String companyCode,
    required String username,
    required String pin,
  });

  /// Creates the CEO's login, a new company with its own login code, and the
  /// CEO's profile in it.
  Future<void> signUpCeo({
    required String name,
    required String companyName,
    required String email,
    required String password,
  });

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}
