import 'package:daily_attendance/app.dart';
import 'package:daily_attendance/core/models/company.dart';
import 'package:daily_attendance/core/models/role_names.dart';
import 'package:daily_attendance/features/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_auth_service.dart';
import 'fake_company_repository.dart';
import 'fake_employee_repository.dart';

void main() {
  group('role names', () {
    test('defaults read naturally in a sentence', () {
      const n = RoleNames.defaults;
      expect(n.supervisor.title, 'Supervisor');
      expect(n.supervisor.titles, 'Supervisors');
      expect(n.director.word, 'director');
      expect(n.employee.words, 'employees');
      expect(n.employee.aWord, 'an employee');
      expect(n.supervisor.aWord, 'a supervisor');
    });

    test("a firm's own words are kept as typed", () {
      const n = RoleNames(director: 'Seth-ji', supervisor: 'Foreman');
      expect(n.director.word, 'Seth-ji');
      expect(n.supervisor.titles, 'Foremen');
      expect(n.supervisor.words, 'Foremen');
      expect(n.employee.word, 'employee');
    });

    test('plurals', () {
      expect(RoleName.pluralOf('Worker'), 'Workers');
      expect(RoleName.pluralOf('Munim'), 'Munims');
      expect(RoleName.pluralOf('Boss'), 'Boss');
      expect(RoleName.pluralOf('Mistry'), 'Mistries');
      expect(RoleName.pluralOf('Karigar'), 'Karigars');
      expect(RoleName.pluralOf('Batch'), 'Batches');
    });

    test(
      'only renamed roles are stored; blank or bad ones use the default',
      () {
        final n = RoleNames.defaults
            .rename('supervisor', ' Foreman ')
            .rename('employee', 'Worker');
        expect(n.toMap(), {'supervisor': 'Foreman', 'employee': 'Worker'});
        expect(RoleNames.fromMap(n.toMap()), n);
        expect(n.rename('supervisor', '  ').supervisor.title, 'Supervisor');
        expect(RoleNames.defaults.allDefault, isTrue);
        final bad = RoleNames.fromMap({'director': '', 'employee': 'x' * 31});
        expect(bad, RoleNames.defaults);
      },
    );

    test('they are kept in the company settings', () {
      final s = CompanySettings.defaults.copyWith(
        roleNames: const RoleNames(employee: 'Worker'),
      );
      expect(s.toMap()['roleNames'], {'employee': 'Worker'});
      expect(CompanySettings.fromMap(s.toMap()), s);
      expect(
        CompanySettings.defaults.toMap().containsKey('roleNames'),
        isFalse,
      );
    });
  });

  group('renamed roles in the app', () {
    late FakeCompanyRepository company;
    late FakeEmployeeRepository employees;

    setUp(() {
      company = FakeCompanyRepository();
      employees = FakeEmployeeRepository();
    });

    Future<void> start(WidgetTester tester, {required bool director}) async {
      tester.view
        ..physicalSize = const Size(420, 2600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      employees.isDirector = director;
      await tester.pumpWidget(
        DailyAttendanceApp(
          auth: FakeAuthService(
            initial: SignedIn(director ? directorUser : supervisorUser),
          ),
          openCompany: (_) => company,
          openEmployees: (_) => employees,
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder tab(String label) => find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text(label),
    );

    testWidgets('the director renames roles in Settings', (tester) async {
      await start(tester, director: true);
      await tester.tap(tab('Settings'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Supervisor'),
        'Foreman',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Employee'),
        'Worker',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(company.company.settings.roleNames.toMap(), {
        'supervisor': 'Foreman',
        'employee': 'Worker',
      });
    });

    testWidgets("everyone's screens follow the company's names", (
      tester,
    ) async {
      employees.settings = CompanySettings.defaults.copyWith(
        roleNames: const RoleNames(
          director: 'Owner',
          supervisor: 'Foreman',
          employee: 'Worker',
        ),
      );
      await start(tester, director: false);

      expect(tab('Workers'), findsOneWidget);
      expect(tab('Employees'), findsNothing);
      // A supervisor without teams is told to ask the Owner.
      expect(find.textContaining('Ask your Owner'), findsOneWidget);

      await tester.tap(find.byTooltip('My profile'));
      await tester.pumpAndSettle();
      expect(find.text('Foreman'), findsOneWidget);
    });
  });
}
