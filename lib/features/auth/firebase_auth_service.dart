import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/data/firestore_helpers.dart' show photoValue, plainData;
import '../../core/models/app_user.dart';
import '../../core/models/company.dart';
import 'auth_service.dart';

/// [AuthService] backed by Firebase phone login and the `users` collection.
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

  /// True while a new company is being saved. During that gap the profile
  /// doesn't exist yet, which is expected.
  bool _creatingCompany = false;

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
    final phone = user.phoneNumber;
    if (phone == null || phone.isEmpty) {
      // An old email login from before phone login.
      _setSession(
        const SessionProblem(
          'This is an old login. Log out and log in again with your phone '
          'number.',
        ),
      );
      return;
    }
    _setSession(const SessionLoading());

    _profileSub = _db
        .collection('users')
        .doc(phone)
        .snapshots()
        .listen(
          (snapshot) {
            final data = snapshot.data();
            if (data == null) {
              // A cache miss isn't an answer; wait for the server.
              if (_creatingCompany || snapshot.metadata.isFromCache) return;
              _setSession(NeedsCompany(phone));
              return;
            }
            final profile = AppUser.fromMap(snapshot.id, plainData(data));
            if (profile == null) {
              _setSession(
                const SessionProblem(
                  'Your account is not set up correctly. '
                  'Ask your director to check it.',
                ),
              );
            } else if (!profile.active) {
              _setSession(
                const SessionProblem(
                  'Your account has been deactivated. '
                  'Ask your director if this is a mistake.',
                ),
              );
            } else {
              _setSession(SignedIn(profile));
            }
          },
          onError: (Object error) {
            if (_creatingCompany) return;
            _setSession(
              SessionProblem(
                'Could not load your account. ${_firestoreMessage(error)}',
              ),
            );
          },
        );
  }

  @override
  Future<CodeSent?> sendCode(String phone, {CodeSent? resend}) {
    final result = Completer<CodeSent?>();
    _auth
        .verifyPhoneNumber(
          phoneNumber: phone,
          forceResendingToken: resend?.resendToken,
          timeout: const Duration(seconds: 60),
          // Android read the SMS (or confirmed the number) by itself.
          verificationCompleted: (credential) async {
            try {
              await _auth.signInWithCredential(credential);
              if (!result.isCompleted) result.complete(null);
            } on FirebaseAuthException catch (e) {
              if (!result.isCompleted) {
                result.completeError(AuthFailure(_authMessage(e.code)));
              }
            }
          },
          verificationFailed: (e) {
            if (!result.isCompleted) {
              result.completeError(AuthFailure(_authMessage(e.code)));
            }
          },
          codeSent: (verificationId, resendToken) {
            if (!result.isCompleted) {
              result.complete(
                CodeSent(
                  phone: phone,
                  verificationId: verificationId,
                  resendToken: resendToken,
                ),
              );
            }
          },
          codeAutoRetrievalTimeout: (_) {},
        )
        .catchError((Object e) {
          if (!result.isCompleted) {
            result.completeError(
              e is FirebaseAuthException
                  ? AuthFailure(_authMessage(e.code))
                  : const AuthFailure('Could not send the code. Try again.'),
            );
          }
        });
    return result.future;
  }

  @override
  Future<void> confirmCode(CodeSent sent, String code) async {
    // Android may already have logged in by reading the SMS itself.
    if (_auth.currentUser?.phoneNumber == sent.phone) return;
    try {
      await _auth.signInWithCredential(
        PhoneAuthProvider.credential(
          verificationId: sent.verificationId,
          smsCode: code.trim(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_authMessage(e.code));
    }
  }

  /// Saves the company and the director's profile together. The security
  /// rules only accept them as a pair, so neither can exist without the
  /// other.
  @override
  Future<void> createCompany({
    required String name,
    required String companyName,
  }) async {
    final phone = _auth.currentUser?.phoneNumber;
    if (phone == null) {
      throw const AuthFailure('Log in with your phone number first.');
    }
    _creatingCompany = true;
    try {
      final companyRef = _db.collection('companies').doc();
      final batch = _db.batch()
        ..set(companyRef, {
          'name': companyName.trim(),
          'createdBy': phone,
          'createdAt': FieldValue.serverTimestamp(),
          'settings': CompanySettings.defaults.toMap(),
        })
        ..set(_db.collection('users').doc(phone), {
          'companyId': companyRef.id,
          'role': UserRole.director.name,
          'name': name.trim(),
          'phone': phone,
          'teamIds': <String>[],
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        });
      await batch.commit();
    } on FirebaseException catch (e) {
      throw AuthFailure(
        'The company could not be saved. ${_firestoreMessage(e)}',
      );
    } finally {
      _creatingCompany = false;
    }
  }

  @override
  Future<void> setMyPhoto(Uint8List? photo) async {
    final current = session;
    if (current is! SignedIn) {
      throw const AuthFailure('Log in first.');
    }
    try {
      await _db.collection('users').doc(current.user.phone).update({
        'photo': photoValue(photo),
      });
    } on FirebaseException catch (e) {
      throw AuthFailure(
        'The photo could not be saved. ${_firestoreMessage(e)}',
      );
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  void dispose() {
    _profileSub?.cancel();
    _authSub.cancel();
    super.dispose();
  }
}

String _authMessage(String code) => switch (code) {
  'invalid-phone-number' => 'That phone number does not look right.',
  'invalid-verification-code' => 'Wrong code. Check the SMS and try again.',
  'session-expired' || 'code-expired' || 'invalid-verification-id' =>
    'The code has expired. Tap "Send again" for a new one.',
  'user-disabled' => 'This login has been switched off.',
  'too-many-requests' ||
  'quota-exceeded' => 'Too many attempts. Wait a while and try again.',
  'network-request-failed' =>
    'No internet connection. Check your connection and try again.',
  'app-not-authorized' || 'missing-client-identifier' =>
    'This copy of the app is not allowed to send login codes. '
        'Contact the app admin.',
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
