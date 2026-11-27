import 'dart:convert';
import 'dart:typed_data';

import 'package:daily_attendance/app.dart';
import 'package:daily_attendance/core/models/app_user.dart';
import 'package:daily_attendance/core/models/company.dart';
import 'package:daily_attendance/core/models/day.dart';
import 'package:daily_attendance/core/models/employee.dart';
import 'package:daily_attendance/core/models/month.dart';
import 'package:daily_attendance/core/models/roster.dart';
import 'package:daily_attendance/core/photos/photo_picker.dart';
import 'package:daily_attendance/features/auth/auth_service.dart';
import 'package:daily_attendance/shared/widgets/person_avatar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_auth_service.dart';
import 'fake_company_repository.dart';
import 'fake_employee_repository.dart';

/// A 1x1 PNG.
final png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  ),
);

class FakePhotoPicker extends PhotoPicker {
  Uint8List? next;
  final asked = <PhotoFrom>[];

  @override
  Future<Uint8List?> pick(PhotoFrom from) async {
    asked.add(from);
    return next;
  }
}

void main() {
  late FakePhotoPicker picker;
  late FakeEmployeeRepository employees;
  late FakeCompanyRepository company;
  late FakeAuthService auth;

  setUp(() {
    picker = FakePhotoPicker()..next = png;
    PhotoPicker.instance = picker;
    employees = FakeEmployeeRepository();
    company = FakeCompanyRepository();
    employees.teams.add(const Team(id: 'team-1', name: 'Sales'));
    employees.myTeamIds = ['team-1'];
  });
  tearDown(() => PhotoPicker.instance = const DevicePhotoPicker());

  Future<void> start(WidgetTester tester, AppUser user) async {
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    employees.isDirector = user.role == UserRole.director;
    auth = FakeAuthService(initial: SignedIn(user));
    await tester.pumpWidget(
      DailyAttendanceApp(
        auth: auth,
        openCompany: (_) => company,
        openEmployees: (_) => employees,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder.last);
    await tester.tap(finder.last);
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String tab) => tap(
    tester,
    find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)),
  );

  testWidgets('the director adds an employee with a photo', (tester) async {
    await start(tester, directorUser);
    await openTab(tester, 'Employees');
    await tap(tester, find.text('Add employee'));
    await tap(tester, find.text('New employee'));

    await tap(tester, find.text('Gallery'));
    expect(picker.asked, [PhotoFrom.gallery]);
    await tester.enterText(find.widgetWithText(TextFormField, 'Emp ID'), 'E7');
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Asha');
    await tap(tester, find.widgetWithText(FilledButton, 'Add employee'));

    expect(employees.employees.single.photo, png);
  });

  testWidgets('the director removes an employee photo', (tester) async {
    employees.employees.add(Employee(empId: 'E1', name: 'Asha', photo: png));
    employees.rosters.add(
      Roster(teamId: 'team-1', month: Month.now(), empIds: ['E1']),
    );
    await start(tester, directorUser);
    await openTab(tester, 'Employees');
    await tap(tester, find.text('Asha'));
    await tap(tester, find.text('Remove'));
    await tap(tester, find.text('Save changes'));

    expect(employees.employees.single.photo, isNull);
    expect(employees.employees.single.name, 'Asha');
  });

  testWidgets('a large photo is refused', (tester) async {
    picker.next = Uint8List(PhotoPicker.maxBytes + 1);
    await start(tester, directorUser);
    await openTab(tester, 'Employees');
    await tap(tester, find.text('Add employee'));
    await tap(tester, find.text('New employee'));
    await tap(tester, find.text('Take photo'));

    expect(find.text('That photo is too large. Try another one.'), findsOne);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('the supervisor sees faces on the attendance sheet', (
    tester,
  ) async {
    employees.employees.addAll([
      Employee(empId: 'E1', name: 'Asha', photo: png),
      const Employee(empId: 'E2', name: 'Bala'),
    ]);
    employees.rosters.add(
      Roster(
        teamId: 'team-1',
        month: Day.today().monthOf,
        empIds: ['E1', 'E2'],
      ),
    );
    await start(tester, supervisorUser);

    final photos = find.byWidgetPredicate(
      (w) => w is PersonAvatar && w.photo != null,
    );
    expect(photos, findsOneWidget);
    // Tapping the face shows it large, with the name.
    await tap(tester, photos);
    expect(find.byType(Dialog), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Asha')),
      findsOneWidget,
    );
  });

  testWidgets('a supervisor sees their profile and adds a photo', (
    tester,
  ) async {
    await start(tester, supervisorUser);
    await tap(tester, find.byTooltip('My profile'));

    expect(find.text('Test Supervisor'), findsOneWidget);
    expect(find.text('+91 90000 00011'), findsOneWidget);
    expect(find.text('Supervisor'), findsOneWidget);
    expect(find.text('Mobile number registered with the app'), findsOneWidget);

    await tap(tester, find.text('Take photo'));
    expect(find.text('Photo saved'), findsOneWidget);
    expect((auth.session as SignedIn).user.photo, png);

    await tap(tester, find.text('Remove'));
    expect((auth.session as SignedIn).user.photo, isNull);
  });

  testWidgets('the director adds a photo for a supervisor', (tester) async {
    company.supervisors.add(
      const AppUser(
        phone: '+919800000001',
        companyId: 'company-1',
        role: UserRole.supervisor,
        name: 'Ravi',
      ),
    );
    await start(tester, directorUser);
    await openTab(tester, 'People');
    await tap(tester, find.text('Ravi'));
    await tap(tester, find.text('Gallery'));
    await tap(tester, find.text('Save changes'));

    expect(company.supervisors.single.photo, png);
    expect(company.supervisors.single.name, 'Ravi');
  });
}
