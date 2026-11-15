import 'package:daily_attendance/app.dart';
import 'package:daily_attendance/core/models/attendance.dart';
import 'package:daily_attendance/core/models/company.dart';
import 'package:daily_attendance/core/models/day.dart';
import 'package:daily_attendance/core/models/employee.dart';
import 'package:daily_attendance/core/models/roster.dart';
import 'package:daily_attendance/features/auth/auth_service.dart';
import 'package:daily_attendance/features/manager/attendance_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_auth_service.dart';
import 'fake_company_repository.dart';
import 'fake_employee_repository.dart';

void main() {
  const rules = CompanySettings.defaults;

  group('an entry', () {
    test('works out hours and the late flag', () {
      final onTime = AttendanceEntry.mark(
        AttendanceStatus.present,
        inTime: '09:45',
        outTime: '18:30',
        settings: rules,
      );
      expect(onTime.minutes, 525);
      expect(onTime.late, isFalse);

      final late = AttendanceEntry.mark(
        AttendanceStatus.present,
        inTime: '09:46',
        settings: rules,
      );
      expect(late.late, isTrue);
      expect(late.minutes, isNull);
    });

    test('absent and leave have no times', () {
      final entry = AttendanceEntry.mark(
        AttendanceStatus.leave,
        inTime: '10:00',
        outTime: '12:00',
        settings: rules,
      );
      expect(entry.inTime, isNull);
      expect(entry.minutes, isNull);
      expect(entry.late, isFalse);
      expect(entry.toMap(), {'status': 'leave'});
    });

    test('a short day becomes a half-day, and a full one present', () {
      final present = AttendanceEntry.mark(
        AttendanceStatus.present,
        inTime: '09:30',
        settings: rules,
      );
      final short = present.withTimes('09:30', '13:00', rules);
      expect(short.status, AttendanceStatus.halfDay);
      expect(short.minutes, 210);
      final full = short.withTimes('09:30', '18:00', rules);
      expect(full.status, AttendanceStatus.present);
    });

    test('reads back what it saves', () {
      final entry = AttendanceEntry.mark(
        AttendanceStatus.halfDay,
        inTime: '10:00',
        outTime: '13:00',
        settings: rules,
        guest: true,
      );
      expect(AttendanceEntry.fromMap(entry.toMap()), entry);
    });
  });

  group('a day', () {
    test('reads and writes yyyy-MM-dd', () {
      expect(Day(2026, 3, 1).key, '2026-03-01');
      expect(Day.tryParse('2026-02-30'), isNull);
      expect(Day.tryParse('2026-2-3'), isNull);
      expect(Day.tryParse('2026-11-15'), Day(2026, 11, 15));
      expect(Day(2026, 3, 1).previous, Day(2026, 2, 28));
      expect(Day(2026, 11, 15).label, 'Sun, 15 Nov');
    });

    test('managers edit today and the edit window only', () {
      final today = Day(2026, 11, 15);
      expect(managerMayEdit(today, today, rules), isTrue);
      expect(managerMayEdit(today.addDays(-7), today, rules), isTrue);
      expect(managerMayEdit(today.addDays(-8), today, rules), isFalse);
      expect(managerMayEdit(today.next, today, rules), isFalse);
    });
  });

  group('the attendance screens', () {
    late FakeEmployeeRepository repo;
    final today = Day.today();

    setUp(() {
      repo = FakeEmployeeRepository();
      repo.teams
        ..add(const Team(id: 'team-1', name: 'Sales'))
        ..add(const Team(id: 'team-2', name: 'Accounts'))
        ..add(const Team(id: 'team-9', name: 'Legal'));
      repo.myTeamIds = ['team-1'];
      repo.employees.addAll(const [
        Employee(empId: 'E1', name: 'Asha'),
        Employee(empId: 'E2', name: 'Bala'),
        Employee(empId: 'E3', name: 'Chitra'),
        Employee(empId: 'E4', name: 'Dev', active: false),
      ]);
      repo.rosters
        ..add(
          Roster(
            teamId: 'team-1',
            month: today.monthOf,
            empIds: ['E1', 'E2', 'E4'],
          ),
        )
        ..add(Roster(teamId: 'team-9', month: today.monthOf, empIds: ['E3']));
    });

    Future<void> start(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(420, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        DailyAttendanceApp(
          auth: FakeAuthService(initial: const SignedIn(managerUser)),
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

    /// The status button [label] on [name]'s card.
    Finder statusButton(String name, String label) => find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(Card)),
      matching: find.widgetWithText(OutlinedButton, label),
    );

    testWidgets('lists the monthly list and saves the marks', (tester) async {
      await start(tester);

      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Bala'), findsOneWidget);
      // Inactive, and not marked that day: left off.
      expect(find.text('Dev'), findsNothing);
      expect(find.text('0 of 2 marked'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);

      await tap(tester, statusButton('Asha', 'Present'));
      expect(find.text('In 9:30 AM'), findsOneWidget);
      await tap(tester, statusButton('Bala', 'Leave'));
      expect(find.textContaining('2 of 2 marked'), findsOneWidget);

      await tap(tester, find.widgetWithText(FilledButton, 'Save'));

      final saved = repo.savedSheet('team-1', today)!;
      expect(saved.entries['E1']!.status, AttendanceStatus.present);
      expect(saved.entries['E1']!.inTime, '09:30');
      expect(saved.entries['E2']!.status, AttendanceStatus.leave);
      expect(find.text('Done'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    });

    testWidgets('marks everyone present in one tap', (tester) async {
      await start(tester);
      await tap(tester, find.text('Mark everyone present'));
      await tap(tester, find.widgetWithText(FilledButton, 'Save'));

      final saved = repo.savedSheet('team-1', today)!;
      expect(saved.entries.keys, unorderedEquals(['E1', 'E2']));
      expect(
        saved.entries.values.map((e) => e.status),
        everyElement(AttendanceStatus.present),
      );
    });

    testWidgets('shows a save error and keeps the changes', (tester) async {
      await start(tester);
      await tap(tester, statusButton('Asha', 'Absent'));
      repo.failNextSave = 'No internet connection. Please try again.';
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Save (1 not marked)'),
      );

      expect(
        find.text('No internet connection. Please try again.'),
        findsOneWidget,
      );
      expect(repo.savedSheet('team-1', today), isNull);
      expect(
        find.widgetWithText(FilledButton, 'Save (1 not marked)'),
        findsOneWidget,
      );
    });

    testWidgets('someone lent to another team shows as working there', (
      tester,
    ) async {
      repo.sheets.add(
        AttendanceSheet(
          teamId: 'team-9',
          date: today,
          entries: {
            'E1': AttendanceEntry.mark(
              AttendanceStatus.present,
              inTime: '09:30',
              settings: rules,
              guest: true,
            ),
          },
        ),
      );
      await start(tester);

      expect(find.text('Working in Legal today (absent here)'), findsOneWidget);
      expect(statusButton('Asha', 'Present'), findsNothing);
      expect(find.text('1 of 2 marked · 1 A'), findsOneWidget);

      await tap(tester, statusButton('Bala', 'Present'));
      await tap(tester, find.widgetWithText(FilledButton, 'Save'));
      final saved = repo.savedSheet('team-1', today)!;
      expect(saved.entries['E1']!.status, AttendanceStatus.absent);
      expect(saved.entries['E1']!.workingIn, 'team-9');
    });

    testWidgets('adds someone from another team for the day', (tester) async {
      await start(tester);
      await tap(tester, find.text('Add someone from another team'));

      // Asha and Bala are already on the sheet; Dev has left.
      expect(find.text('Asha'), findsNothing);
      expect(find.text('Dev'), findsNothing);
      expect(find.text('E3\nIn Legal'), findsOneWidget);
      await tap(tester, find.text('Chitra'));

      expect(find.textContaining('From another team today'), findsOneWidget);
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Save (2 not marked)'),
      );
      final guest = repo.savedSheet('team-1', today)!.entries['E3']!;
      expect(guest.guest, isTrue);
      expect(guest.status, AttendanceStatus.present);
    });

    testWidgets('a manager with several teams sees which are done', (
      tester,
    ) async {
      repo.myTeamIds = ['team-1', 'team-2'];
      repo.rosters.add(
        Roster(teamId: 'team-2', month: today.monthOf, empIds: ['E3']),
      );
      repo.sheets.add(
        AttendanceSheet(
          teamId: 'team-2',
          date: today,
          entries: {
            'E3': AttendanceEntry.mark(
              AttendanceStatus.absent,
              settings: rules,
            ),
          },
        ),
      );
      await start(tester);

      expect(find.text('All my teams: 1 of 2 done'), findsOneWidget);
      expect(find.text('Accounts · Done'), findsOneWidget);
      expect(find.text('Sales · Pending'), findsOneWidget);

      // Switching with unsaved changes asks first.
      await tap(tester, statusButton('Asha', 'Present'));
      await tap(tester, find.text('Accounts · Done'));
      expect(find.text('Discard changes?'), findsOneWidget);
      await tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Discard'),
        ),
      );
      expect(find.text('Chitra'), findsOneWidget);
      expect(find.text('Asha'), findsNothing);
    });

    testWidgets('past days can be corrected within the edit window', (
      tester,
    ) async {
      repo.settings = rules.copyWith(managerEditDays: 2);
      await start(tester);
      await tap(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Past days'),
        ),
      );

      final yesterday = today.previous;
      expect(find.text(yesterday.longLabel), findsOneWidget);
      expect(find.text(today.addDays(-2).longLabel), findsOneWidget);
      expect(find.text(today.addDays(-3).longLabel), findsNothing);

      await tap(tester, find.text('Sales').first);
      await tap(tester, find.text('Mark everyone present'));
      await tap(tester, find.widgetWithText(FilledButton, 'Save'));

      expect(repo.savedSheet('team-1', yesterday), isNotNull);
      expect(repo.savedSheet('team-1', today), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Done · 2 marked'), findsOneWidget);
    });
  });
}
