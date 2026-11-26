import 'package:daily_attendance/app.dart';
import 'package:daily_attendance/core/models/company.dart';
import 'package:daily_attendance/core/models/employee.dart';
import 'package:daily_attendance/core/models/month.dart';
import 'package:daily_attendance/core/models/roster.dart';
import 'package:daily_attendance/features/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_auth_service.dart';
import 'fake_company_repository.dart';
import 'fake_employee_repository.dart';

void main() {
  late FakeEmployeeRepository repo;

  /// Opens the Employees tab as the manager, or as the director (who sees
  /// every team and is the only one who adds or changes employees).
  Future<void> openEmployees(
    WidgetTester tester, {
    bool asDirector = false,
  }) async {
    tester.view
      ..physicalSize = const Size(400, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo.isDirector = asDirector;
    await tester.pumpWidget(
      DailyAttendanceApp(
        auth: FakeAuthService(
          initial: SignedIn(asDirector ? directorUser : managerUser),
        ),
        openCompany: (_) => FakeCompanyRepository(),
        openEmployees: (_) => repo,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Employees'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String label, String text) =>
      tester.enterText(find.widgetWithText(TextFormField, label), text);

  Future<void> tapButton(WidgetTester tester, String text) async {
    final label = find.text(text, skipOffstage: false);
    final button = find.ancestor(
      of: label,
      matching: find.byWidgetPredicate(
        (w) => w is ButtonStyleButton || w is FloatingActionButton,
        skipOffstage: false,
      ),
    );
    final target = button.evaluate().isNotEmpty ? button.last : label.last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  setUp(() => repo = FakeEmployeeRepository());

  final thisMonth = Month.now();

  /// Two of the manager's own teams, plus one they don't look after.
  void seedTeams() {
    repo.teams
      ..add(const Team(id: 'team-1', name: 'Sales'))
      ..add(const Team(id: 'team-2', name: 'Accounts'))
      ..add(const Team(id: 'team-9', name: 'Legal'));
    repo.myTeamIds = ['team-1', 'team-2'];
  }

  void onList(String teamId, Month month, List<String> empIds) =>
      repo.rosters.add(Roster(teamId: teamId, month: month, empIds: empIds));

  /// The director's Add button offers a new employee or someone already in
  /// the company.
  Future<void> startAdding(WidgetTester tester, String choice) async {
    await tapButton(tester, 'Add employee');
    await tester.tap(find.text(choice));
    await tester.pumpAndSettle();
  }

  testWidgets('a manager without teams is told to ask the director', (
    tester,
  ) async {
    repo.teams.add(const Team(id: 'team-9', name: 'Legal'));
    await openEmployees(tester);
    expect(find.text('No teams yet'), findsOneWidget);
    expect(find.text('Add employee'), findsNothing);
  });

  testWidgets("the director's new employee goes on this month's list", (
    tester,
  ) async {
    repo.teams.add(const Team(id: 'team-1', name: 'Sales'));
    await openEmployees(tester, asDirector: true);
    // One team: named, nothing to choose. This month is shown.
    expect(find.text('Sales'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text(thisMonth.label), findsOneWidget);
    expect(find.text('Nobody on the list'), findsOneWidget);

    await startAdding(tester, 'New employee');
    await fill(tester, 'Emp ID', 'emp-7');
    await fill(tester, 'Name', '  Asha Rao ');
    await fill(tester, 'Designation (optional)', 'Accountant');
    await tapButton(tester, 'Add employee');

    final added = repo.employees.single;
    expect(added.empId, 'EMP-7');
    expect(added.name, 'Asha Rao');
    expect(added.designation, 'Accountant');
    expect(repo.savedList('team-1', thisMonth), ['EMP-7']);
    expect(find.text('Asha Rao'), findsOneWidget);
    expect(find.text('EMP-7 · Accountant'), findsOneWidget);
    expect(find.text('1 employee'), findsOneWidget);
  });

  testWidgets('a new month starts with last month’s people', (tester) async {
    seedTeams();
    repo.employees
      ..add(const Employee(empId: 'S1', name: 'Asha'))
      ..add(const Employee(empId: 'S2', name: 'Bilal'));
    onList('team-1', thisMonth.previous, ['S1', 'S2']);
    await openEmployees(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sales'));
    await tester.pumpAndSettle();

    // Nothing saved for this month yet, but the same people are listed.
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Bilal'), findsOneWidget);
    expect(
      find.textContaining('Same people as ${thisMonth.previous.label}'),
      findsOneWidget,
    );
    expect(repo.savedList('team-1', thisMonth), isNull);

    // Bilal moved: take him off. Saved for this month only.
    await tester.tap(find.text('Bilal'));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Take off Sales list');
    expect(find.text('Take Bilal off Sales?'), findsOneWidget);
    await tapButton(tester, 'Take off');

    expect(repo.savedList('team-1', thisMonth), ['S1']);
    expect(repo.savedList('team-1', thisMonth.previous), ['S1', 'S2']);
    expect(find.text('Bilal'), findsNothing);
    expect(find.textContaining('Same people as'), findsNothing);
    // He's still a company employee.
    expect(repo.employees, hasLength(2));
  });

  testWidgets('an Emp ID is required and must be free', (tester) async {
    seedTeams();
    repo.employees.add(const Employee(empId: 'E2', name: 'Bilal'));
    await openEmployees(tester, asDirector: true);

    await startAdding(tester, 'New employee');
    await tapButton(tester, 'Add employee');
    expect(find.text('Enter the Emp ID'), findsOneWidget);
    expect(find.text("Enter the employee's name"), findsOneWidget);

    await fill(tester, 'Emp ID', 'e2');
    await fill(tester, 'Name', 'Someone');
    await tapButton(tester, 'Add employee');
    expect(find.textContaining('Already used by Bilal'), findsOneWidget);
    expect(repo.employees, hasLength(1));
  });

  testWidgets('the manager puts someone from another team on their list', (
    tester,
  ) async {
    seedTeams();
    repo.employees
      ..add(const Employee(empId: 'L1', name: 'Leela', designation: 'Lawyer'))
      ..add(const Employee(empId: 'A1', name: 'Bilal'))
      ..add(const Employee(empId: 'N1', name: 'Nobody yet'))
      ..add(const Employee(empId: 'X1', name: 'Gone', active: false));
    onList('team-9', thisMonth, ['L1', 'X1']);
    onList('team-2', thisMonth, ['A1']);
    await openEmployees(tester);

    // Accounts (first by name) is on screen. A manager can't add someone
    // new, so Add goes straight to the staff list.
    await tapButton(tester, 'Add to team');
    expect(find.text('New employee'), findsNothing);
    expect(find.text('Add to Accounts'), findsOneWidget);
    // Bilal is already on Accounts' list; people who left aren't offered.
    expect(find.text('Leela'), findsOneWidget);
    expect(find.text('L1 · Lawyer\nIn Legal'), findsOneWidget);
    expect(find.text('N1\nNot on any team this month'), findsOneWidget);
    expect(find.text('Bilal'), findsNothing);
    expect(find.text('Gone'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No match'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'lee');
    await tester.pump();

    await tester.tap(find.text('Leela'));
    await tester.pumpAndSettle();
    expect(find.text('Add Leela to Accounts?'), findsOneWidget);
    await tapButton(tester, 'Add');

    expect(repo.savedList('team-2', thisMonth), ['A1', 'L1']);
    // Still on Legal's list too.
    expect(repo.savedList('team-9', thisMonth), ['L1', 'X1']);
    expect(find.text('L1 · Lawyer\nAlso in Legal'), findsOneWidget);
  });

  testWidgets('the team selector switches between teams', (tester) async {
    seedTeams();
    repo.employees
      ..add(const Employee(empId: 'S1', name: 'Asha'))
      ..add(const Employee(empId: 'A1', name: 'Bilal'));
    onList('team-1', thisMonth, ['S1']);
    onList('team-2', thisMonth, ['A1']);
    await openEmployees(tester);

    // Only the manager's own teams; sorted by name, so Accounts is first.
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(find.text('Bilal'), findsOneWidget);
    expect(find.text('Asha'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Sales'));
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Bilal'), findsNothing);
  });

  testWidgets("the director sees every team and adds to the one on screen", (
    tester,
  ) async {
    seedTeams();
    repo.employees.add(const Employee(empId: 'S1', name: 'Asha'));
    onList('team-1', thisMonth, ['S1']);
    onList('team-2', thisMonth, const []);
    await openEmployees(tester, asDirector: true);

    // Legal too, though it isn't a team the director "manages".
    expect(find.byType(ChoiceChip), findsNWidgets(3));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sales'));
    await tester.pumpAndSettle();

    await startAdding(tester, 'New employee');
    await fill(tester, 'Emp ID', 'S2');
    await fill(tester, 'Name', 'Chitra');
    await tapButton(tester, 'Add employee');
    expect(repo.savedList('team-1', thisMonth), ['S1', 'S2']);
    expect(repo.savedList('team-2', thisMonth), isEmpty);
  });

  testWidgets('past months are view only; next month can be planned', (
    tester,
  ) async {
    seedTeams();
    repo.employees.add(const Employee(empId: 'A1', name: 'Bilal'));
    onList('team-2', thisMonth.previous, ['A1']);
    await openEmployees(tester);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text(thisMonth.previous.label), findsOneWidget);
    expect(find.textContaining('view only'), findsOneWidget);
    expect(find.text('Add to team'), findsNothing);
    await tester.tap(find.text('Bilal'));
    await tester.pumpAndSettle();
    expect(find.text('Take off Accounts list'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
    }
    expect(find.text(thisMonth.next.label), findsOneWidget);
    expect(find.text('Add to team'), findsOneWidget);
    // No further than next month.
    final next = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_right),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets("a manager can't change an employee's details", (tester) async {
    seedTeams();
    repo.employees.add(
      const Employee(empId: 'A1', name: 'Bilal', designation: 'Clerk'),
    );
    onList('team-2', thisMonth, ['A1']);
    await openEmployees(tester);

    await tester.tap(find.text('Bilal'));
    await tester.pumpAndSettle();
    expect(find.text('Employee'), findsOneWidget);
    expect(find.text('Save changes'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.textContaining('Only the director can change'), findsOneWidget);
    final name = tester.widget<TextField>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Name'),
        matching: find.byType(TextField),
      ),
    );
    expect(name.readOnly, isTrue);
    // Moving them off the team is still the manager's to do.
    expect(find.text('Take off Accounts list'), findsOneWidget);
  });

  testWidgets('the director deactivates an employee', (tester) async {
    seedTeams();
    repo.employees.add(const Employee(empId: 'A1', name: 'Bilal'));
    onList('team-2', thisMonth, ['A1']);
    await openEmployees(tester, asDirector: true);

    await tester.tap(find.text('Bilal'));
    await tester.pumpAndSettle();
    await fill(tester, 'Name', 'Bilal Khan');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save changes');

    // Deactivating asks first.
    expect(find.text('Deactivate Bilal?'), findsOneWidget);
    await tapButton(tester, 'Deactivate');

    expect(repo.employees.single.name, 'Bilal Khan');
    expect(repo.employees.single.active, isFalse);
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('0 employees · 1 inactive'), findsOneWidget);
  });

  group('months and lists', () {
    test('months step, sort and print', () {
      const dec = Month(2026, 12);
      expect(dec.key, '2026-12');
      expect(dec.next, const Month(2027, 1));
      expect(const Month(2027, 1).previous, dec);
      expect(dec.minus(12), const Month(2025, 12));
      expect(dec.label, 'December 2026');
      expect(Month.tryParse('2026-03'), const Month(2026, 3));
      expect(Month.tryParse('2026-13'), isNull);
      expect(const Month(2026, 9) < const Month(2026, 10), isTrue);
    });

    test('a month without its own list copies the latest earlier one', () {
      final rosters = [
        const Roster(teamId: 't1', month: Month(2026, 8), empIds: ['A']),
        const Roster(teamId: 't1', month: Month(2026, 10), empIds: ['A', 'B']),
        const Roster(teamId: 't2', month: Month(2026, 11), empIds: ['C']),
      ];
      final nov = EffectiveRoster.of(rosters, 't1', const Month(2026, 11));
      expect(nov.empIds, ['A', 'B']);
      expect(nov.copiedFrom, const Month(2026, 10));
      final oct = EffectiveRoster.of(rosters, 't1', const Month(2026, 10));
      expect(oct.copiedFrom, isNull);
      final sep = EffectiveRoster.of(rosters, 't1', const Month(2026, 9));
      expect(sep.empIds, ['A']);
      final jul = EffectiveRoster.of(rosters, 't1', const Month(2026, 7));
      expect(jul.empIds, isEmpty);
    });
  });

  test('Emp IDs sort like a register', () {
    final ids = ['EMP-10', 'emp-2', 'B1', 'EMP-9', '100', '20'];
    ids.sort(compareNatural);
    expect(ids, ['20', '100', 'B1', 'emp-2', 'EMP-9', 'EMP-10']);
  });

  test('Emp ID rules', () {
    expect(Employee.normalizeEmpId(' emp-01 '), 'EMP-01');
    expect(Employee.isValidEmpId('EMP-01'), isTrue);
    expect(Employee.isValidEmpId('102'), isTrue);
    expect(Employee.isValidEmpId('-1'), isFalse);
    expect(Employee.isValidEmpId('A/B'), isFalse);
    expect(Employee.isValidEmpId('A' * 21), isFalse);
  });
}
