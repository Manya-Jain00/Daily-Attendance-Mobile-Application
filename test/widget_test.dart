import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daily_attendance/app.dart';
import 'package:daily_attendance/features/auth/auth_service.dart';

import 'fake_auth_service.dart';
import 'fake_company_repository.dart';
import 'fake_employee_repository.dart';

void main() {
  Future<FakeAuthService> startApp(
    WidgetTester tester, {
    Session initial = const SignedOut(),
  }) async {
    final auth = FakeAuthService(initial: initial);
    await tester.pumpWidget(
      DailyAttendanceApp(
        auth: auth,
        openCompany: (_) => FakeCompanyRepository(),
        openEmployees: (_) => FakeEmployeeRepository(),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  Future<void> tapLogIn(WidgetTester tester) async {
    final button = find.widgetWithText(FilledButton, 'Log in');
    await tester.ensureVisible(button);
    await tester.tap(button);
  }

  Future<void> chooseCeoLogin(WidgetTester tester) async {
    await tester.tap(find.text('CEO'));
    await tester.pumpAndSettle();
  }

  Future<void> logIn(WidgetTester tester, String email, String password) async {
    await chooseCeoLogin(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), email);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      password,
    );
    await tapLogIn(tester);
    await tester.pumpAndSettle();
  }

  Future<void> logInManager(
    WidgetTester tester,
    String code,
    String username,
    String pin,
  ) async {
    Future<void> fill(String label, String text) =>
        tester.enterText(find.widgetWithText(TextFormField, label), text);
    await fill('Company code', code);
    await fill('Username', username);
    await fill('PIN', pin);
    await tapLogIn(tester);
    await tester.pumpAndSettle();
  }

  testWidgets('signed-out user sees the login screen', (tester) async {
    await startApp(tester);

    expect(find.text('Daily Attendance'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
  });

  testWidgets('shows the splash while the session is loading', (tester) async {
    final auth = FakeAuthService(initial: const SessionLoading());
    await tester.pumpWidget(
      DailyAttendanceApp(
        auth: auth,
        openCompany: (_) => FakeCompanyRepository(),
        openEmployees: (_) => FakeEmployeeRepository(),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Log in'), findsNothing);
  });

  testWidgets('CEO logs in and lands on the CEO dashboard', (tester) async {
    await startApp(tester);
    await logIn(tester, 'ceo@test.com', 'password1');

    for (final tab in ['Dashboard', 'Teams', 'Managers', 'Reports']) {
      expect(find.text(tab), findsWidgets);
    }
    expect(find.text('Past days'), findsNothing);
    // The CEO sees the code to give to managers.
    expect(find.text('ACME22'), findsOneWidget);
  });

  testWidgets('manager logs in with company code, username and PIN', (
    tester,
  ) async {
    await startApp(tester);
    // Code and username are forgiving about case and spaces.
    await logInManager(tester, 'acme22 ', 'Ravi', '123456');

    for (final tab in ['Today', 'Employees', 'Past days']) {
      expect(find.text(tab), findsWidgets);
    }
    expect(find.text('Managers'), findsNothing);
  });

  testWidgets('wrong password shows an error and stays on login', (
    tester,
  ) async {
    await startApp(tester);
    await logIn(tester, 'ceo@test.com', 'nope');

    expect(find.text('Wrong email or password.'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('wrong PIN shows an error and stays on login', (tester) async {
    await startApp(tester);
    await logInManager(tester, 'ACME22', 'ravi', '000000');

    expect(find.text('Wrong company code, username or PIN.'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('empty manager form shows validation messages', (tester) async {
    await startApp(tester);
    await tapLogIn(tester);
    await tester.pumpAndSettle();

    expect(find.text('Enter your company code'), findsOneWidget);
    expect(find.text('Enter your username'), findsOneWidget);
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('empty CEO form shows validation messages', (tester) async {
    await startApp(tester);
    await chooseCeoLogin(tester);
    await tapLogIn(tester);
    await tester.pumpAndSettle();

    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('log out returns to the login screen', (tester) async {
    await startApp(tester, initial: const SignedIn(managerUser));
    expect(find.text('Past days'), findsWidgets);

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('a deactivated account sees the problem screen', (tester) async {
    final auth = await startApp(tester, initial: const SignedIn(managerUser));
    auth.session = const SessionProblem('Your account has been deactivated.');
    await tester.pumpAndSettle();

    expect(find.text('Your account has been deactivated.'), findsOneWidget);

    await tester.tap(find.text('Back to login'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('CEO sign-up creates the company and opens the CEO home', (
    tester,
  ) async {
    await startApp(tester);
    await tester.ensureVisible(find.text('Create a company account'));
    await tester.tap(find.text('Create a company account'));
    await tester.pumpAndSettle();

    Future<void> fill(String label, String text) =>
        tester.enterText(find.widgetWithText(TextFormField, label), text);
    await fill('Company name', 'Acme Pvt Ltd');
    await fill('Your name', 'New Boss');
    await fill('Email', 'boss@acme.com');
    await fill('Password', 'longenough');
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('NEWC23'), findsOneWidget);
  });

  testWidgets('sign-up rejects a short password', (tester) async {
    await startApp(tester);
    await tester.ensureVisible(find.text('Create a company account'));
    await tester.tap(find.text('Create a company account'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'short',
    );
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(find.text('Enter the company name'), findsOneWidget);
  });

  testWidgets('forgot password sends a reset email', (tester) async {
    final auth = await startApp(tester);
    await chooseCeoLogin(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'ceo@test.com',
    );
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(auth.resetEmails, ['ceo@test.com']);
  });
}
