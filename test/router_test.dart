import 'package:flutter_test/flutter_test.dart';

import 'package:daily_attendance/features/auth/auth_service.dart';
import 'package:daily_attendance/routing/app_router.dart';

import 'fake_auth_service.dart';

void main() {
  group('redirectFor', () {
    test('signed out: only login is open', () {
      const s = SignedOut();
      expect(redirectFor(s, AppRoutes.login), isNull);
      expect(redirectFor(s, AppRoutes.companySetup), AppRoutes.login);
      expect(redirectFor(s, AppRoutes.director), AppRoutes.login);
      expect(redirectFor(s, AppRoutes.manager), AppRoutes.login);
      expect(redirectFor(s, AppRoutes.splash), AppRoutes.login);
    });

    test('a manager can never open the director area', () {
      const s = SignedIn(managerUser);
      expect(redirectFor(s, AppRoutes.director), AppRoutes.manager);
      expect(redirectFor(s, AppRoutes.login), AppRoutes.manager);
      expect(redirectFor(s, AppRoutes.manager), isNull);
    });

    test('a director is sent to the director area', () {
      const s = SignedIn(directorUser);
      expect(redirectFor(s, AppRoutes.manager), AppRoutes.director);
      expect(redirectFor(s, AppRoutes.companySetup), AppRoutes.director);
      expect(redirectFor(s, AppRoutes.director), isNull);
    });

    test('loading keeps login forms open, otherwise shows the splash', () {
      const s = SessionLoading();
      expect(redirectFor(s, AppRoutes.login), isNull);
      expect(redirectFor(s, AppRoutes.companySetup), isNull);
      expect(redirectFor(s, AppRoutes.splash), isNull);
      expect(redirectFor(s, AppRoutes.director), AppRoutes.splash);
    });

    test('a number with no company only sees company set-up', () {
      const s = NeedsCompany('+919876543210');
      expect(redirectFor(s, AppRoutes.companySetup), isNull);
      expect(redirectFor(s, AppRoutes.login), AppRoutes.companySetup);
      expect(redirectFor(s, AppRoutes.director), AppRoutes.companySetup);
      expect(redirectFor(s, AppRoutes.manager), AppRoutes.companySetup);
    });

    test('an account problem always shows the problem screen', () {
      const s = SessionProblem('x');
      expect(redirectFor(s, AppRoutes.director), AppRoutes.accountProblem);
      expect(redirectFor(s, AppRoutes.login), AppRoutes.accountProblem);
      expect(redirectFor(s, AppRoutes.accountProblem), isNull);
    });
  });
}
