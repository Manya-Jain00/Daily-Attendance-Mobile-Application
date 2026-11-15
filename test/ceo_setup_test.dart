import 'package:daily_attendance/app.dart';
import 'package:daily_attendance/core/models/app_user.dart';
import 'package:daily_attendance/core/models/company.dart';
import 'package:daily_attendance/features/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_auth_service.dart';
import 'fake_company_repository.dart';
import 'fake_employee_repository.dart';

void main() {
  late FakeCompanyRepository repo;

  Future<void> openTab(WidgetTester tester, String tab) async {
    // Phone width, and tall enough that the longest form fits on screen.
    tester.view
      ..physicalSize = const Size(400, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = FakeAuthService(initial: const SignedIn(ceoUser));
    await tester.pumpWidget(
      DailyAttendanceApp(
        auth: app,
        openCompany: (_) => repo,
        openEmployees: (_) => FakeEmployeeRepository(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String label, String text) =>
      tester.enterText(find.widgetWithText(TextFormField, label), text);

  Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pump();
  }

  /// Taps a button by its text, preferring a real button over a title with
  /// the same words (e.g. "Add manager" is both).
  Future<void> tapButton(WidgetTester tester, String text) async {
    // Includes buttons scrolled out of view; ensureVisible brings them back.
    final label = find.text(text, skipOffstage: false);
    final button = find.ancestor(
      of: label,
      matching: find.byWidgetPredicate(
        (w) => w is ButtonStyleButton,
        skipOffstage: false,
      ),
    );
    final target = button.evaluate().isNotEmpty ? button.last : label.last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  setUp(() => repo = FakeCompanyRepository());

  group('teams', () {
    testWidgets('the CEO adds a team', (tester) async {
      await openTab(tester, 'Teams');
      expect(find.text('No teams yet'), findsOneWidget);

      await tapButton(tester, 'Add team');
      await fill(tester, 'Team name', '  Marketing ');
      await tapButton(tester, 'Add');

      expect(repo.teams.map((t) => t.name), ['Marketing']);
      expect(find.text('Marketing'), findsOneWidget);
      expect(find.text('No manager yet'), findsOneWidget);
    });

    testWidgets('two teams cannot share a name', (tester) async {
      repo.teams.add(const Team(id: 't1', name: 'Finance'));
      await openTab(tester, 'Teams');

      await tapButton(tester, 'Add team');
      await fill(tester, 'Team name', 'finance');
      await tapButton(tester, 'Add');

      expect(
        find.text('There is already a team with this name'),
        findsOneWidget,
      );
      expect(repo.teams, hasLength(1));
    });

    testWidgets('rename and delete a team', (tester) async {
      repo.teams.add(const Team(id: 't1', name: 'Legl'));
      repo.managers.add(_manager('m1', 'Ravi', teamIds: ['t1']));
      await openTab(tester, 'Teams');
      expect(find.text('Ravi'), findsOneWidget);

      await tester.tap(find.byTooltip('Options for Legl'));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Rename');
      await fill(tester, 'Team name', 'Legal');
      await tapButton(tester, 'Save');
      expect(repo.teams.single.name, 'Legal');

      await tester.tap(find.byTooltip('Options for Legal'));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Delete');
      expect(find.textContaining('Its manager'), findsOneWidget);
      await tapButton(tester, 'Delete');

      expect(repo.teams, isEmpty);
      expect(repo.managers.single.teamIds, isEmpty);
    });

    testWidgets('a team with employees cannot be deleted', (tester) async {
      repo.teams.add(const Team(id: 't1', name: 'Sales'));
      repo.employeeCounts['t1'] = 3;
      await openTab(tester, 'Teams');

      await tester.tap(find.byTooltip('Options for Sales'));
      await tester.pumpAndSettle();
      await tapButton(tester, 'Delete');
      await tapButton(tester, 'Delete');

      expect(find.textContaining('still has employees'), findsOneWidget);
      expect(repo.teams, hasLength(1));
    });
  });

  group('managers', () {
    testWidgets('the CEO adds a manager and sees their login details', (
      tester,
    ) async {
      repo.teams
        ..add(const Team(id: 't1', name: 'Sales'))
        ..add(const Team(id: 't2', name: 'Legal'));
      await openTab(tester, 'Managers');
      expect(find.text('No managers yet'), findsOneWidget);

      await tapButton(tester, 'Add manager');
      await fill(tester, 'Name', 'Ravi Kumar');
      await fill(tester, 'Username', 'Ravi');
      await fill(tester, 'PIN', '482913');
      await tester.tap(find.widgetWithText(FilterChip, 'Sales'));
      await tester.tap(find.widgetWithText(FilterChip, 'Legal'));
      await tester.pump();
      await tapButton(tester, 'Add manager');

      expect(find.text('Manager added'), findsOneWidget);
      expect(
        find.text('Company code: ACME22\nUsername: ravi\nPIN: 482913'),
        findsOneWidget,
      );
      await tapButton(tester, 'Done');

      final added = repo.managers.single;
      expect(added.name, 'Ravi Kumar');
      expect(added.username, 'ravi');
      expect(added.teamIds, ['t2', 't1']);
      expect(repo.pins['ravi'], '482913');
      // Back on the list, with their teams.
      expect(find.text('ravi · Legal, Sales'), findsOneWidget);
    });

    testWidgets('checks the username and PIN', (tester) async {
      repo.managers.add(_manager('m1', 'Ravi'));
      await openTab(tester, 'Managers');

      await tapButton(tester, 'Add manager');
      await fill(tester, 'Name', 'Another Ravi');
      await fill(tester, 'Username', 'RAVI');
      await fill(tester, 'PIN', '123');
      await tapButton(tester, 'Add manager');

      expect(find.text('This username is already taken'), findsOneWidget);
      expect(find.text('Use at least 6 digits'), findsOneWidget);
      expect(repo.managers, hasLength(1));
    });

    testWidgets('random PIN fills in 6 digits', (tester) async {
      await openTab(tester, 'Managers');
      await tapButton(tester, 'Add manager');

      await tapTooltip(tester, 'Make a random PIN');

      final pin = tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'PIN'))
          .controller!
          .text;
      expect(pin, matches(RegExp(r'^\d{6}$')));
    });

    testWidgets('the CEO edits teams and deactivates a manager', (
      tester,
    ) async {
      repo.teams
        ..add(const Team(id: 't1', name: 'Sales'))
        ..add(const Team(id: 't2', name: 'Legal'));
      repo.managers.add(_manager('m1', 'Ravi', teamIds: ['t1']));
      await openTab(tester, 'Managers');

      await tester.tap(find.text('Ravi'));
      await tester.pumpAndSettle();
      // The username is part of the login, so it's shown but not editable.
      expect(find.widgetWithText(TextFormField, 'Username'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'Legal'));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tapButton(tester, 'Save changes');
      expect(find.text('Deactivate Ravi?'), findsOneWidget);
      await tapButton(tester, 'Deactivate');

      final edited = repo.managers.single;
      expect(edited.active, isFalse);
      // In the order the teams are listed (by name).
      expect(edited.teamIds, ['t2', 't1']);
      expect(find.text('Inactive'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('the CEO changes the rules and saves them', (tester) async {
      await openTab(tester, 'Settings');
      expect(find.text('9:30 AM'), findsOneWidget);
      expect(find.text('7 d'), findsOneWidget);

      await tapTooltip(tester, 'More edit window days');
      await tapTooltip(tester, 'Less half-day hours');
      await fill(tester, 'Company name', 'Acme Pvt Ltd');
      await tapButton(tester, 'Save changes');

      expect(repo.company.name, 'Acme Pvt Ltd');
      expect(repo.company.settings.managerEditDays, 8);
      expect(repo.company.settings.halfDayBelowHours, 3.5);
      expect(find.text('Settings saved'), findsOneWidget);
    });

    testWidgets('undo puts back the saved settings', (tester) async {
      await openTab(tester, 'Settings');
      await tapTooltip(tester, 'More edit window days');
      expect(find.text('8 d'), findsOneWidget);

      await tapButton(tester, 'Undo changes');
      expect(find.text('7 d'), findsOneWidget);
    });
  });

  group('CompanySettings', () {
    test('falls back to defaults for bad stored values', () {
      final s = CompanySettings.fromMap({
        'officeStart': '9:30',
        'officeEnd': '17:00',
        'halfDayBelowHours': 'four',
      });
      expect(s.officeStart, '09:30');
      expect(s.officeEnd, '17:00');
      expect(s.halfDayBelowHours, 4);
      expect(CompanySettings.fromMap(null), CompanySettings.defaults);
    });
  });
}

AppUser _manager(String uid, String name, {List<String> teamIds = const []}) =>
    AppUser(
      uid: uid,
      companyId: 'company-1',
      companyCode: 'ACME22',
      role: UserRole.manager,
      name: name,
      email: '${name.toLowerCase()}@acme22.login.test',
      username: name.toLowerCase(),
      teamIds: teamIds,
    );
