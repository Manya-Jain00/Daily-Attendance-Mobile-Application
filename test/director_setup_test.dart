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
      ..physicalSize = const Size(400, 2600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = FakeAuthService(initial: const SignedIn(directorUser));
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
  /// the same words (e.g. "Add supervisor" is both).
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

  /// The People tab's "Add" asks which kind of person to add.
  Future<void> startAdding(WidgetTester tester, String kind) async {
    await tapButton(tester, 'Add');
    await tester.tap(find.text(kind));
    await tester.pumpAndSettle();
  }

  setUp(() => repo = FakeCompanyRepository());

  group('teams', () {
    testWidgets('the director adds a team', (tester) async {
      await openTab(tester, 'Teams');
      expect(find.text('No teams yet'), findsOneWidget);

      await tapButton(tester, 'Add team');
      await fill(tester, 'Team name', '  Marketing ');
      await tapButton(tester, 'Add');

      expect(repo.teams.map((t) => t.name), ['Marketing']);
      expect(find.text('Marketing'), findsOneWidget);
      expect(find.text('No supervisor yet'), findsOneWidget);
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
      repo.supervisors.add(_supervisor('m1', 'Ravi', teamIds: ['t1']));
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
      expect(find.textContaining('Its supervisor'), findsOneWidget);
      await tapButton(tester, 'Delete');

      expect(repo.teams, isEmpty);
      expect(repo.supervisors.single.teamIds, isEmpty);
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

  group('supervisors', () {
    testWidgets('the director adds a supervisor by their mobile number', (
      tester,
    ) async {
      repo.teams
        ..add(const Team(id: 't1', name: 'Sales'))
        ..add(const Team(id: 't2', name: 'Legal'));
      await openTab(tester, 'People');
      expect(find.text('No one added yet'), findsOneWidget);

      await startAdding(tester, 'Supervisor');
      await fill(tester, 'Name', 'Ravi Kumar');
      await fill(tester, 'Mobile number', '98765 43210');
      await tester.tap(find.widgetWithText(FilterChip, 'Sales'));
      await tester.tap(find.widgetWithText(FilterChip, 'Legal'));
      await tester.pump();
      await tapButton(tester, 'Add supervisor');

      expect(find.text('Supervisor added'), findsOneWidget);
      expect(
        find.textContaining('Ravi Kumar can now log in with +91 98765 43210'),
        findsOneWidget,
      );
      await tapButton(tester, 'Done');

      final added = repo.supervisors.single;
      expect(added.name, 'Ravi Kumar');
      expect(added.phone, '+919876543210');
      expect(added.teamIds, ['t2', 't1']);
      // Back on the list, with their teams.
      expect(find.text('+91 98765 43210 · Legal, Sales'), findsOneWidget);
    });

    testWidgets('checks the number', (tester) async {
      repo.supervisors.add(_supervisor('m1', 'Ravi'));
      await openTab(tester, 'People');

      await startAdding(tester, 'Supervisor');
      await fill(tester, 'Name', 'Another Ravi');
      await fill(tester, 'Mobile number', '12345');
      await tapButton(tester, 'Add supervisor');
      expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);

      // Already in the company, typed another way.
      await fill(tester, 'Mobile number', '+91 98000 00001');
      await tapButton(tester, 'Add supervisor');
      expect(
        find.text('A supervisor with this number is already added'),
        findsOneWidget,
      );
      expect(repo.supervisors, hasLength(1));
    });

    testWidgets('the director edits teams and deactivates a supervisor', (
      tester,
    ) async {
      repo.teams
        ..add(const Team(id: 't1', name: 'Sales'))
        ..add(const Team(id: 't2', name: 'Legal'));
      repo.supervisors.add(_supervisor('m1', 'Ravi', teamIds: ['t1']));
      await openTab(tester, 'People');

      await tester.tap(find.text('Ravi'));
      await tester.pumpAndSettle();
      // The number is their login, so it's shown but not editable.
      expect(find.widgetWithText(TextFormField, 'Mobile number'), findsNothing);
      expect(find.text('+91 98000 00001'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Legal'));
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tapButton(tester, 'Save changes');
      expect(find.text('Deactivate Ravi?'), findsOneWidget);
      await tapButton(tester, 'Deactivate');

      final edited = repo.supervisors.single;
      expect(edited.active, isFalse);
      // In the order the teams are listed (by name).
      expect(edited.teamIds, ['t2', 't1']);
      expect(find.text('Inactive'), findsOneWidget);
    });
  });

  group('accountants', () {
    testWidgets('the director adds an accountant by their mobile number', (
      tester,
    ) async {
      repo.teams.add(const Team(id: 't1', name: 'Sales'));
      repo.supervisors.add(_supervisor('m1', 'Ravi', teamIds: ['t1']));
      await openTab(tester, 'People');

      await startAdding(tester, 'Accountant');
      expect(find.text('Add accountant'), findsWidgets);
      // An accountant sees every team, so there are none to pick.
      expect(find.byType(FilterChip), findsNothing);

      // A supervisor's number can't be used again.
      await fill(tester, 'Name', 'Meena');
      await fill(tester, 'Mobile number', '98000 00001');
      await tapButton(tester, 'Add accountant');
      expect(
        find.text('A supervisor with this number is already added'),
        findsOneWidget,
      );

      await fill(tester, 'Mobile number', '98111 22233');
      await tapButton(tester, 'Add accountant');
      expect(find.text('Accountant added'), findsOneWidget);
      await tapButton(tester, 'Done');

      final added = repo.accountants.single;
      expect(added.name, 'Meena');
      expect(added.phone, '+919811122233');
      expect(added.role, UserRole.accountant);
      expect(added.teamIds, isEmpty);
      expect(repo.supervisors, hasLength(1));
      // Listed in its own section.
      expect(find.text('Accountants'), findsOneWidget);
      expect(find.text('+91 98111 22233 · View only'), findsOneWidget);
    });

    testWidgets('the director renames and deactivates an accountant', (
      tester,
    ) async {
      repo.accountants.add(
        const AppUser(
          phone: '+919811122233',
          companyId: 'company-1',
          role: UserRole.accountant,
          name: 'Meena',
        ),
      );
      await openTab(tester, 'People');

      await tester.tap(find.text('Meena'));
      await tester.pumpAndSettle();
      expect(find.text('Edit accountant'), findsOneWidget);
      await fill(tester, 'Name', 'Meena Shah');
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tapButton(tester, 'Save changes');
      await tapButton(tester, 'Deactivate');

      final edited = repo.accountants.single;
      expect(edited.name, 'Meena Shah');
      expect(edited.active, isFalse);
      expect(find.text('Inactive'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('the director changes the rules and saves them', (
      tester,
    ) async {
      await openTab(tester, 'Settings');
      expect(find.text('9:30 AM'), findsOneWidget);
      expect(find.text('7 d'), findsOneWidget);

      await tapTooltip(tester, 'More edit window days');
      await tapTooltip(tester, 'Less half-day hours');
      await fill(tester, 'Company name', 'Acme Pvt Ltd');
      await tapButton(tester, 'Save changes');

      expect(repo.company.name, 'Acme Pvt Ltd');
      expect(repo.company.settings.supervisorEditDays, 8);
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

/// [id] is 'm1' to 'm9', giving +919800000001 to +919800000009.
AppUser _supervisor(
  String id,
  String name, {
  List<String> teamIds = const [],
}) => AppUser(
  phone: '+91980000000${id.substring(1)}',
  companyId: 'company-1',
  role: UserRole.supervisor,
  name: name,
  teamIds: teamIds,
);
