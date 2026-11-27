import 'dart:typed_data';

import 'package:daily_attendance/core/models/app_user.dart';
import 'package:daily_attendance/features/auth/auth_service.dart';

/// In-memory [AuthService] for tests: knows a fixed set of numbers. Every
/// code is [goodCode].
class FakeAuthService extends AuthService {
  FakeAuthService({Session initial = const SignedOut()}) : _session = initial;

  static const goodCode = '123456';

  /// Number -> profile. A number not in here logs in to [NeedsCompany].
  final profiles = <String, AppUser>{
    directorUser.phone: directorUser,
    supervisorUser.phone: supervisorUser,
  };

  /// Every number a code was sent to, in order.
  final codesSentTo = <String>[];

  Session _session;

  @override
  Session get session => _session;

  set session(Session value) {
    _session = value;
    notifyListeners();
  }

  @override
  Future<CodeSent?> sendCode(String phone, {CodeSent? resend}) async {
    codesSentTo.add(phone);
    return CodeSent(phone: phone, verificationId: 'v-$phone');
  }

  @override
  Future<void> confirmCode(CodeSent sent, String code) async {
    if (code != goodCode) {
      throw const AuthFailure('Wrong code. Check the SMS and try again.');
    }
    final profile = profiles[sent.phone];
    session = profile == null ? NeedsCompany(sent.phone) : SignedIn(profile);
  }

  @override
  Future<void> createCompany({
    required String name,
    required String companyName,
  }) async {
    final current = session;
    if (current is! NeedsCompany) {
      throw const AuthFailure('Log in with your phone number first.');
    }
    final user = AppUser(
      phone: current.phone,
      companyId: 'new-company',
      role: UserRole.director,
      name: name.trim(),
    );
    profiles[current.phone] = user;
    session = SignedIn(user);
  }

  @override
  Future<void> setMyPhoto(Uint8List? photo) async {
    final current = session;
    if (current is! SignedIn) throw const AuthFailure('Log in first.');
    final user = current.user.withPhoto(photo);
    profiles[user.phone] = user;
    session = SignedIn(user);
  }

  @override
  Future<void> signOut() async => session = const SignedOut();
}

const directorUser = AppUser(
  phone: '+919000000001',
  companyId: 'company-1',
  role: UserRole.director,
  name: 'Test director',
);

const supervisorUser = AppUser(
  phone: '+919000000011',
  companyId: 'company-1',
  role: UserRole.supervisor,
  name: 'Test Supervisor',
  teamIds: ['team-1'],
);

const accountantUser = AppUser(
  phone: '+919000000021',
  companyId: 'company-1',
  role: UserRole.accountant,
  name: 'Test Accountant',
);
