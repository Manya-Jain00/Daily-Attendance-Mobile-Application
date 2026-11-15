import 'package:daily_attendance/core/models/app_user.dart';
import 'package:daily_attendance/features/auth/auth_service.dart';

/// In-memory [AuthService] for tests: knows a fixed set of logins.
class FakeAuthService extends AuthService {
  FakeAuthService({Session initial = const SignedOut()}) : _session = initial;

  /// CEO email -> (password, profile)
  final accounts = <String, (String, AppUser)>{
    'ceo@test.com': ('password1', ceoUser),
  };

  /// 'CODE/username' -> (PIN, profile)
  final managerAccounts = <String, (String, AppUser)>{
    'ACME22/ravi': ('123456', managerUser),
  };

  Session _session;

  @override
  Session get session => _session;

  set session(Session value) {
    _session = value;
    notifyListeners();
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    final account = accounts[email.trim()];
    if (account == null || account.$1 != password) {
      throw const AuthFailure('Wrong email or password.');
    }
    session = SignedIn(account.$2);
  }

  @override
  Future<void> signInManager({
    required String companyCode,
    required String username,
    required String pin,
  }) async {
    final key =
        '${companyCode.trim().toUpperCase()}/${username.trim().toLowerCase()}';
    final account = managerAccounts[key];
    if (account == null || account.$1 != pin) {
      throw const AuthFailure('Wrong company code, username or PIN.');
    }
    session = SignedIn(account.$2);
  }

  @override
  Future<void> signUpCeo({
    required String name,
    required String companyName,
    required String email,
    required String password,
  }) async {
    if (accounts.containsKey(email.trim())) {
      throw const AuthFailure('An account with this email already exists.');
    }
    final user = AppUser(
      uid: 'new-ceo',
      companyId: 'new-company',
      companyCode: 'NEWC23',
      role: UserRole.ceo,
      name: name,
      email: email.trim(),
    );
    accounts[email.trim()] = (password, user);
    session = SignedIn(user);
  }

  final resetEmails = <String>[];

  @override
  Future<void> sendPasswordReset(String email) async => resetEmails.add(email);

  @override
  Future<void> signOut() async => session = const SignedOut();
}

const ceoUser = AppUser(
  uid: 'ceo-1',
  companyId: 'company-1',
  companyCode: 'ACME22',
  role: UserRole.ceo,
  name: 'Test CEO',
  email: 'ceo@test.com',
);

const managerUser = AppUser(
  uid: 'manager-1',
  companyId: 'company-1',
  companyCode: 'ACME22',
  role: UserRole.manager,
  name: 'Test Manager',
  email: 'ravi@acme22.login.test',
  username: 'ravi',
  teamIds: ['team-1'],
);
