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

  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.widgetWithText(FilledButton, label);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> enterPhone(WidgetTester tester, String phone) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mobile number'),
      phone,
    );
    await tapButton(tester, 'Send code');
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Code'), code);
    await tapButton(tester, 'Log in');
  }

  Future<void> logIn(WidgetTester tester, String phone) async {
    await enterPhone(tester, phone);
    await enterCode(tester, FakeAuthService.goodCode);
  }

  testWidgets('signed-out user sees the phone login', (tester) async {
    await startApp(tester);

    expect(find.text('Daily Attendance'), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);
    // One login for everyone: no director/supervisor switch.
    expect(find.text('Director'), findsNothing);
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
    expect(find.text('Send code'), findsNothing);
  });

  testWidgets('the director logs in and lands on the director dashboard', (
    tester,
  ) async {
    final auth = await startApp(tester);
    // A local 10-digit number is taken as Indian.
    await logIn(tester, '90000 00001');

    expect(auth.codesSentTo, ['+919000000001']);
    for (final tab in ['Dashboard', 'Teams', 'People', 'Reports']) {
      expect(find.text(tab), findsWidgets);
    }
    expect(find.text('Past days'), findsNothing);
  });

  testWidgets('a supervisor logs in with their number and code', (
    tester,
  ) async {
    await startApp(tester);
    await logIn(tester, '+91 90000 00011');

    for (final tab in ['Today', 'Employees', 'Past days']) {
      expect(find.text(tab), findsWidgets);
    }
    expect(find.text('People'), findsNothing);
  });

  testWidgets('the code screen shows the number and can go back', (
    tester,
  ) async {
    await startApp(tester);
    await enterPhone(tester, '9000000011');

    expect(find.textContaining('+91 90000 00011'), findsOneWidget);
    expect(find.text('Send again in 30s'), findsOneWidget);

    await tester.tap(find.text('Change number'));
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);
  });

  testWidgets('a wrong code shows an error and stays on the code screen', (
    tester,
  ) async {
    await startApp(tester);
    await enterPhone(tester, '9000000011');
    await enterCode(tester, '000000');

    expect(
      find.text('Wrong code. Check the SMS and try again.'),
      findsOneWidget,
    );
    expect(find.text('Enter the code'), findsOneWidget);
  });

  testWidgets('checks the number and the code', (tester) async {
    final auth = await startApp(tester);
    await tapButton(tester, 'Send code');
    expect(find.text('Enter the mobile number'), findsOneWidget);

    await enterPhone(tester, '12345');
    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    expect(auth.codesSentTo, isEmpty);

    await enterPhone(tester, '9000000011');
    await enterCode(tester, '12');
    expect(find.text('The code has 6 digits'), findsOneWidget);
  });

  testWidgets('log out returns to the login screen', (tester) async {
    await startApp(tester, initial: const SignedIn(supervisorUser));
    expect(find.text('Past days'), findsWidgets);

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('Send code'), findsOneWidget);
  });

  testWidgets('a deactivated account sees the problem screen', (tester) async {
    final auth = await startApp(
      tester,
      initial: const SignedIn(supervisorUser),
    );
    auth.session = const SessionProblem('Your account has been deactivated.');
    await tester.pumpAndSettle();

    expect(find.text('Your account has been deactivated.'), findsOneWidget);

    await tester.tap(find.text('Back to login'));
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);
  });

  testWidgets('a new number sets up a company and opens the director home', (
    tester,
  ) async {
    await startApp(tester);
    await logIn(tester, '9876543210');

    expect(find.text('Set up a new company'), findsOneWidget);
    // A supervisor who landed here is told what to do.
    expect(find.textContaining('+91 98765 43210'), findsOneWidget);

    Future<void> fill(String label, String text) =>
        tester.enterText(find.widgetWithText(TextFormField, label), text);
    await fill('Company name', 'Acme Pvt Ltd');
    await fill('Your name', 'New Boss');
    await tapButton(tester, 'Create company');

    expect(find.text('Dashboard'), findsWidgets);
  });

  testWidgets('company set-up needs both names, and can log out', (
    tester,
  ) async {
    await startApp(tester, initial: const NeedsCompany('+919876543210'));
    await tapButton(tester, 'Create company');

    expect(find.text('Enter the company name'), findsOneWidget);
    expect(find.text('Enter your name'), findsOneWidget);

    await tester.ensureVisible(find.text('Log out'));
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);
  });
}
