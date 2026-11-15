import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/manager_login.dart';
import '../../core/models/app_user.dart';
import '../../core/models/company.dart';
import 'auth_service.dart';

/// [AuthService] backed by Firebase Authentication and the `users` collection.
class FirebaseAuthService extends AuthService {
  FirebaseAuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _db = firestore ?? FirebaseFirestore.instance {
    _authSub = _auth.authStateChanges().listen(_onAuthUserChanged);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  late final StreamSubscription<User?> _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;

  /// True between creating a CEO's login and saving their profile. During that
  /// gap the profile doesn't exist yet, which is expected, not a problem.
  bool _signingUp = false;

  Session _session = const SessionLoading();

  @override
  Session get session => _session;

  void _setSession(Session session) {
    _session = session;
    notifyListeners();
  }

  void _onAuthUserChanged(User? user) {
    _profileSub?.cancel();
    _profileSub = null;

    if (user == null) {
      _setSession(const SignedOut());
      return;
    }
    // While signing up, stay on the sign-up screen until the profile exists.
    if (!_signingUp) _setSession(const SessionLoading());

    _profileSub = _db
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snapshot) {
            final data = snapshot.data();
            if (data == null) {
              // A cache miss isn't an answer; wait for the server.
              if (_signingUp || snapshot.metadata.isFromCache) return;
              _setSession(
                const SessionProblem(
                  'This login is not linked to any company yet. '
                  'Ask your admin to add you.',
                ),
              );
              return;
            }
            final profile = AppUser.fromMap(snapshot.id, data);
            if (profile == null) {
              _setSession(
                const SessionProblem(
                  'Your account is not set up correctly. '
                  'Ask your admin to check it.',
                ),
              );
            } else if (!profile.active) {
              _setSession(
                const SessionProblem(
                  'Your account has been deactivated. '
                  'Ask your admin if this is a mistake.',
                ),
              );
            } else {
              _setSession(SignedIn(profile));
            }
          },
          onError: (Object error) {
            if (_signingUp) return;
            _setSession(
              SessionProblem(
                'Could not load your account. ${_firestoreMessage(error)}',
              ),
            );
          },
        );
  }

  @override
  Future<void> signIn({required String email, required String password}) {
    return _guard(
      () => _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );
  }

  @override
  Future<void> signInManager({
    required String companyCode,
    required String username,
    required String pin,
  }) {
    return _guard(
      () => _auth.signInWithEmailAndPassword(
        email: ManagerLogin.email(companyCode: companyCode, username: username),
        password: pin,
      ),
      wrongLogin: 'Wrong company code, username or PIN.',
    );
  }

  @override
  Future<void> signUpCeo({
    required String name,
    required String companyName,
    required String email,
    required String password,
  }) async {
    _signingUp = true;
    try {
      final credential = await _guard(
        () => _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        ),
      );
      final user = credential.user!;
      try {
        await _createCompany(user: user, name: name, companyName: companyName);
      } catch (_) {
        // Remove the half-made login so the same email can be used again.
        try {
          await user.delete();
        } catch (_) {
          await _auth.signOut();
        }
        rethrow;
      }
    } finally {
      _signingUp = false;
    }
  }

  /// Saves the company, its login code and the CEO's profile together. The
  /// security rules only accept them as a set, so none can exist without the
  /// others.
  ///
  /// `companyCodes/{code}` keeps codes unique: the rules refuse to write over
  /// a code that's taken, so on a clash we try again with a fresh code.
  Future<void> _createCompany({
    required User user,
    required String name,
    required String companyName,
  }) async {
    const attempts = 3;
    for (var attempt = 1; ; attempt++) {
      final code = ManagerLogin.newCompanyCode();
      final companyRef = _db.collection('companies').doc();
      final batch = _db.batch()
        ..set(companyRef, {
          'name': companyName.trim(),
          'code': code,
          'createdBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'settings': CompanySettings.defaults.toMap(),
        })
        ..set(_db.collection('companyCodes').doc(code), {
          'companyId': companyRef.id,
        })
        ..set(_db.collection('users').doc(user.uid), {
          'companyId': companyRef.id,
          'companyCode': code,
          'role': UserRole.ceo.name,
          'name': name.trim(),
          'email': user.email,
          'teamIds': <String>[],
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      try {
        await batch.commit();
        return;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied' && attempt < attempts) continue;
        throw AuthFailure(
          'Your login was made, but the company could not be saved. '
          '${_firestoreMessage(e)}',
        );
      }
    }
  }

  @override
  Future<void> sendPasswordReset(String email) {
    return _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));
  }

  @override
  Future<void> signOut() => _auth.signOut();

  /// Runs a Firebase Auth call, turning its errors into readable messages.
  Future<T> _guard<T>(
    Future<T> Function() action, {
    String wrongLogin = 'Wrong email or password.',
  }) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_authMessage(e.code, wrongLogin));
    }
  }

  @override
  void dispose() {
    _profileSub?.cancel();
    _authSub.cancel();
    super.dispose();
  }
}

String _authMessage(String code, String wrongLogin) => switch (code) {
  'invalid-email' => 'That email address does not look right.',
  'invalid-credential' || 'wrong-password' || 'user-not-found' => wrongLogin,
  'user-disabled' => 'This login has been switched off.',
  'email-already-in-use' =>
    'An account with this email already exists. Try logging in instead.',
  'weak-password' => 'Choose a stronger password (at least 6 characters).',
  'too-many-requests' => 'Too many attempts. Wait a few minutes and try again.',
  'network-request-failed' =>
    'No internet connection. Check your connection and try again.',
  _ => 'Something went wrong ($code). Please try again.',
};

String _firestoreMessage(Object error) {
  final code = error is FirebaseException ? error.code : null;
  return switch (code) {
    'permission-denied' => 'Access was refused by the server.',
    'unavailable' => 'Check your internet connection and try again.',
    null => 'Please try again.',
    _ => 'Please try again ($code).',
  };
}
