import 'package:go_router/go_router.dart';

import '../core/models/app_user.dart';
import '../features/auth/account_problem_screen.dart';
import '../features/auth/auth_service.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/ceo/ceo_home_screen.dart';
import '../features/manager/manager_home_screen.dart';

abstract final class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const signup = '/signup';
  static const accountProblem = '/account-problem';
  static const ceo = '/ceo';
  static const manager = '/manager';

  static String homeFor(UserRole role) => switch (role) {
    UserRole.ceo => ceo,
    UserRole.manager => manager,
  };
}

/// Re-checks [redirectFor] whenever the login state changes, so logging in,
/// logging out or being deactivated always lands on the right screen.
GoRouter createAppRouter(AuthService auth) => GoRouter(
  initialLocation: AppRoutes.splash,
  refreshListenable: auth,
  redirect: (context, state) =>
      redirectFor(auth.session, state.matchedLocation),
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.signup,
      builder: (context, state) => const SignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.accountProblem,
      builder: (context, state) => const AccountProblemScreen(),
    ),
    GoRoute(
      path: AppRoutes.ceo,
      builder: (context, state) => const CeoHomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.manager,
      builder: (context, state) => const ManagerHomeScreen(),
    ),
  ],
);

/// Where someone at [location] should be sent, or null to let them stay.
String? redirectFor(Session session, String location) {
  final onAuthScreen =
      location == AppRoutes.login || location == AppRoutes.signup;

  return switch (session) {
    // Keep the login/sign-up form on screen (it shows its own spinner) so an
    // error can still be shown there; everywhere else, wait on the splash.
    SessionLoading() =>
      onAuthScreen || location == AppRoutes.splash ? null : AppRoutes.splash,
    SignedOut() => onAuthScreen ? null : AppRoutes.login,
    SessionProblem() =>
      location == AppRoutes.accountProblem ? null : AppRoutes.accountProblem,
    // Each role may only be in its own area.
    SignedIn(:final user) =>
      location == AppRoutes.homeFor(user.role)
          ? null
          : AppRoutes.homeFor(user.role),
  };
}
