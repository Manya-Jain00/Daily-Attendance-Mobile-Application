import 'package:flutter_test/flutter_test.dart';

import 'package:daily_attendance/features/auth/auth_service.dart';
import 'package:daily_attendance/routing/app_router.dart';

import 'fake_auth_service.dart';

void main() {
  group('redirectFor', () {
    test('signed out: only login and sign-up are open', () {
      const s = SignedOut();
      expect(redirectFor(s, AppRoutes.login), isNull);
      expect(redirectFor(s, AppRoutes.signup), isNull);
      expect(redirectFor(s, AppRoutes.ceo), AppRoutes.login);
      expect(redirectFor(s, AppRoutes.manager), AppRoutes.login);
      expect(redirectFor(s, AppRoutes.splash), AppRoutes.login);
    });

    test('a manager can never open the CEO area', () {
      const s = SignedIn(managerUser);
      expect(redirectFor(s, AppRoutes.ceo), AppRoutes.manager);
      expect(redirectFor(s, AppRoutes.login), AppRoutes.manager);
      expect(redirectFor(s, AppRoutes.manager), isNull);
    });

    test('a CEO is sent to the CEO area', () {
      const s = SignedIn(ceoUser);
      expect(redirectFor(s, AppRoutes.manager), AppRoutes.ceo);
      expect(redirectFor(s, AppRoutes.signup), AppRoutes.ceo);
      expect(redirectFor(s, AppRoutes.ceo), isNull);
    });

    test('loading keeps login forms open, otherwise shows the splash', () {
      const s = SessionLoading();
      expect(redirectFor(s, AppRoutes.login), isNull);
      expect(redirectFor(s, AppRoutes.signup), isNull);
      expect(redirectFor(s, AppRoutes.splash), isNull);
      expect(redirectFor(s, AppRoutes.ceo), AppRoutes.splash);
    });

    test('an account problem always shows the problem screen', () {
      const s = SessionProblem('x');
      expect(redirectFor(s, AppRoutes.ceo), AppRoutes.accountProblem);
      expect(redirectFor(s, AppRoutes.login), AppRoutes.accountProblem);
      expect(redirectFor(s, AppRoutes.accountProblem), isNull);
    });
  });
}
