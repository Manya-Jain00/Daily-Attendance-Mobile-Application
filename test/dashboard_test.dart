import 'package:daily_attendance/app.dart';
import 'package:daily_attendance/core/models/attendance.dart';
import 'package:daily_attendance/core/models/company.dart';
import 'package:daily_attendance/core/models/day.dart';
import 'package:daily_attendance/core/models/employee.dart';
import 'package:daily_attendance/core/models/overview.dart';
import 'package:daily_attendance/core/models/roster.dart';
import 'package:daily_attendance/core/models/team_day.dart';
import 'package:daily_attendance/features/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_auth_service.dart';
import 'fake_company_repository.dart';
import 'fake_employee_repository.dart';

void main() {
  const rules = CompanySettings.defaults;
  final today = Day.today();

  AttendanceEntry present(String inTime, {String? out, bool guest = false}) =>
      AttendanceEntry.mark(
        AttendanceStatus.present,
        inTime: inTime,
        outTime: out,
        settings: rules,
        guest: guest,
      );
  final absent = AttendanceEntry.mark(AttendanceStatus.absent, settings: rules);
  final leave = AttendanceEntry.mark(AttendanceStatus.leave, settings: rules);

  late FakeEmployeeRepository repo;

  setUp(() {
    repo = FakeEmployeeRepository()..isDirector = true;
    repo.teams
      ..add(const Team(id: 'team-1', name: 'Sales'))
      ..add(const Team(id: 'team-2', name: 'Accounts'));
    repo.employees.addAll(const [
      Employee(empId: 'E1', name: 'Asha'),
      Employee(empId: 'E2', name: 'Bala'),
      Employee(empId: 'E3', name: 'Chitra'),
    ]);
    // From last month, so the lists also cover days early in this month's
    // previous month.
    final month = today.monthOf.previous;
    repo.rosters
      ..add(Roster(teamId: 'team-1', month: month, empIds: ['E1', 'E2']))
      ..add(Roster(teamId: 'team-2', month: month, empIds: ['E3']));
  });

  group('the overview', () {
    test('counts someone lent to another team once', () {
      final data = DayData(
        date: today,
        sheets: [
          AttendanceSheet(
            teamId: 'team-1',
            date: today,
            entries: {
              'E1': present('09:30'),
              'E3': present('09:30', guest: true),
            },
          ),
        ],
        rosters: repo.rosters,
        employees: repo.employees,
      );
      final team2 = StatusCounts.ofRows(data.rows('team-2'));
      expect(team2.lentOut, 1);
      expect(team2.done, isTrue);

      final company = StatusCounts.ofCompany([
        data.rows('team-1'),
        data.rows('team-2'),
      ]);
      expect(company.total, 3);
      expect(company.present, 2);
      expect(company.pending, 1);
    });

    test('history skips "working in" entries and is newest first', () {
      final days = historyOf('E3', [
        AttendanceSheet(
          teamId: 'team-2',
          date: today,
          entries: {'E3': const AttendanceEntry.workingIn('team-1')},
        ),
        AttendanceSheet(
          teamId: 'team-1',
          date: today,
          entries: {'E3': present('10:00', out: '18:00', guest: true)},
        ),
        AttendanceSheet(
          teamId: 'team-2',
          date: today.previous,
          entries: {'E3': leave},
        ),
      ]);
      expect(days.map((d) => d.date), [today, today.previous]);
      expect(days.first.entries.single.teamId, 'team-1');

      final summary = HistorySummary(days);
      expect(summary.present, 1);
      expect(summary.leave, 1);
      expect(summary.late, 1);
      expect(summary.minutes, 480);
    });
  });

  group('the director dashboard', () {
    Future<void> start(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(360, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        DailyAttendanceApp(
          auth: FakeAuthService(initial: const SignedIn(directorUser)),
          openCompany: (_) => FakeCompanyRepository(),
          openEmployees: (_) => repo,
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    testWidgets("shows each team's day", (tester) async {
      repo.sheets.add(
        AttendanceSheet(
          teamId: 'team-1',
          date: today,
          entries: {
            'E1': present('10:00'),
            'E2': absent,
            'E3': present('09:30', guest: true),
          },
        ),
      );
      await start(tester);

      expect(find.text('Today · ${today.label}'), findsOneWidget);
      expect(
        find.text('3 people · 2 of 2 teams done · 1 late'),
        findsOneWidget,
      );
      expect(find.text('Done\n2 present · 1 absent · 1 late'), findsOneWidget);
      expect(find.text('Done\n1 in another team'), findsOneWidget);

      // Opens the team's full sheet, with every team to switch to.
      await tap(tester, find.text('Sales'));
      expect(find.text('All teams: 2 of 2 done'), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Chitra'), findsOneWidget);
    });

    testWidgets('a pending team shows how many are left', (tester) async {
      repo.sheets.add(
        AttendanceSheet(
          teamId: 'team-1',
          date: today,
          entries: {'E1': present('09:30')},
        ),
      );
      await start(tester);
      expect(find.text('1 of 2 not marked\n1 present'), findsOneWidget);
      expect(find.text('Not marked yet'), findsOneWidget);
    });

    testWidgets('the director corrects a day older than the edit window', (
      tester,
    ) async {
      await start(tester);
      for (var i = 0; i < 10; i++) {
        await tap(tester, find.byTooltip('Previous day'));
      }
      final day = today.addDays(-10);
      expect(find.text(day.longLabel), findsOneWidget);

      await tap(tester, find.text('Sales'));
      expect(find.textContaining('view only'), findsNothing);
      await tap(tester, find.text('Mark everyone present'));
      await tap(tester, find.widgetWithText(FilledButton, 'Save'));
      expect(repo.savedSheet('team-1', day)!.entries.keys, {'E1', 'E2'});

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Done\n2 present'), findsOneWidget);

      await tap(tester, find.text('Today'));
      expect(find.text('Today · ${today.label}'), findsOneWidget);
    });

    testWidgets("shows an employee's history", (tester) async {
      repo.sheets.add(
        AttendanceSheet(
          teamId: 'team-1',
          date: today,
          entries: {'E1': present('10:00', out: '18:30')},
        ),
      );
      await start(tester);
      await tap(tester, find.text('Employee history'));
      await tester.enterText(find.byType(TextField), 'ash');
      await tester.pumpAndSettle();
      expect(find.text('Bala'), findsNothing);
      await tap(tester, find.text('Asha'));

      expect(
        find.text('1 day recorded · 1 late · 8 h 30 m worked'),
        findsOneWidget,
      );
      expect(find.text('${today.longLabel} · Present'), findsOneWidget);
      expect(
        find.text('Sales · 10:00 AM – 6:30 PM · 8 h 30 m'),
        findsOneWidget,
      );

      // Back goes to the list first, then to the dashboard.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Search by name or Emp ID'), findsOneWidget);
    });
  });

  group('the accountant', () {
    Future<void> start(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(360, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repo
        ..isDirector = false
        ..isAccountant = true;
      final company = FakeCompanyRepository();
      company.teams.addAll(repo.teams);
      await tester.pumpWidget(
        DailyAttendanceApp(
          auth: FakeAuthService(initial: const SignedIn(accountantUser)),
          openCompany: (_) => company,
          openEmployees: (_) => repo,
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> tap(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Finder tab(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

    testWidgets("has the director's Dashboard, Teams and Reports only", (
      tester,
    ) async {
      await start(tester);
      expect(tab('Dashboard'), findsOneWidget);
      expect(tab('Teams'), findsOneWidget);
      expect(tab('Reports'), findsOneWidget);
      expect(tab('Employees'), findsNothing);
      expect(tab('People'), findsNothing);
      expect(tab('Settings'), findsNothing);

      // Teams are listed, with nothing to add, rename or delete.
      await tap(tester, tab('Teams'));
      expect(find.text('Add team'), findsNothing);
      expect(find.byTooltip('Options for Sales'), findsNothing);
    });

    testWidgets('sees any team sheet, view only, with nothing to save', (
      tester,
    ) async {
      repo.sheets.add(
        AttendanceSheet(
          teamId: 'team-1',
          date: today,
          entries: {'E1': present('10:00')},
        ),
      );
      await start(tester);

      await tap(tester, find.text('Sales'));
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('View only.'), findsOneWidget);
      expect(find.text('Mark the rest present'), findsNothing);
      expect(find.text('Add someone from another team'), findsNothing);

      // The status buttons are there to read, but can't be pressed, so no
      // Save bar ever appears.
      final absentButton = find.widgetWithText(OutlinedButton, 'Absent');
      expect(absentButton, findsWidgets);
      expect(
        tester.widget<OutlinedButton>(absentButton.first).onPressed,
        isNull,
      );
      await tester.tap(absentButton.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
      expect(repo.savedSheet('team-1', today)!.entries.keys, {'E1'});
    });

    testWidgets('opens employee history and the reports', (tester) async {
      await start(tester);
      await tap(tester, find.text('Employee history'));
      expect(find.text('Search by name or Emp ID'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tap(tester, tab('Reports'));
      expect(find.text('Share as Excel file'), findsOneWidget);
    });
  });
}
