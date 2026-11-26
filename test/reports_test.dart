import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:daily_attendance/core/export/attendance_workbook.dart';
import 'package:daily_attendance/core/export/xlsx.dart';
import 'package:daily_attendance/core/models/attendance.dart';
import 'package:daily_attendance/core/models/attendance_report.dart';
import 'package:daily_attendance/core/models/company.dart';
import 'package:daily_attendance/core/models/day.dart';
import 'package:daily_attendance/core/models/day_value.dart';
import 'package:daily_attendance/core/models/employee.dart';
import 'package:daily_attendance/core/models/month.dart';
import 'package:daily_attendance/core/models/roster.dart';
import 'package:daily_attendance/features/director/reports_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_employee_repository.dart';

/// The files inside an `.xlsx`, as text.
Map<String, String> unzip(Uint8List bytes) => {
  for (final f in ZipDecoder().decodeBytes(bytes))
    f.name: utf8.decode(f.content),
};

void main() {
  group('Dihadi (day value)', () {
    test("matches the firm's table for whole hours", () {
      const table = {
        0: 0.0,
        1: 0.125,
        2: 0.25,
        3: 0.5,
        4: 0.5,
        5: 0.625,
        6: 0.75,
        7: 0.875,
        8: 1.0,
        9: 1.0,
        10: 1.25,
        11: 1.25,
        12: 1.5,
        13: 1.625,
        14: 1.75,
        15: 1.75,
        16: 2.0,
      };
      table.forEach((hours, value) {
        expect(dayValue(hours * 60), value, reason: '$hours h');
      });
    });

    test('a half hour adds 0.0625', () {
      expect(dayValue(30), 0.0625);
      expect(dayValue(8 * 60 + 30), 1.0625);
      expect(dayValue(9 * 60 + 30), 1.0625);
      expect(dayValue(3 * 60 + 30), 0.5625);
    });

    test('rounds to the nearest half hour', () {
      expect(dayValue(8 * 60 + 14), 1.0); // 8 h
      expect(dayValue(8 * 60 + 15), 1.0625); // 8 h 30 m
      expect(dayValue(8 * 60 + 44), 1.0625); // 8 h 30 m
      expect(dayValue(8 * 60 + 45), 1.0); // 9 h
      expect(dayValue(14), 0);
    });

    test('past 16 hours, 1/8 a day per hour', () {
      expect(dayValue(17 * 60), 2.125);
      expect(dayValue(18 * 60 + 30), 2.3125);
    });
  });

  const rules = CompanySettings.defaults;
  // The page opens on last month.
  final month = Month.now().previous;
  Day day(int d) => Day(month.year, month.month, d);

  AttendanceEntry worked(
    AttendanceStatus status,
    String inTime,
    String? out, {
    bool guest = false,
  }) => AttendanceEntry.mark(
    status,
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
      ..add(const Team(id: 'team-1', name: 'Sector 122'))
      ..add(const Team(id: 'team-2', name: 'Accounts'));
    repo.employees.addAll(const [
      Employee(empId: 'E10', name: 'Suraj', designation: 'Labour'),
      Employee(empId: 'E2', name: 'Bala, Jr.'),
      Employee(empId: 'E3', name: 'Chitra'),
      Employee(empId: 'E4', name: 'Dev', active: false),
    ]);
    repo.rosters
      ..add(Roster(teamId: 'team-1', month: month, empIds: ['E10', 'E2']))
      ..add(Roster(teamId: 'team-2', month: month, empIds: ['E3', 'E4']));
    repo.sheets.addAll([
      AttendanceSheet(
        teamId: 'team-1',
        date: day(1),
        entries: {
          // 12 h: 1.5
          'E10': worked(AttendanceStatus.present, '08:00', '20:00'),
          'E2': absent,
        },
      ),
      AttendanceSheet(
        teamId: 'team-1',
        date: day(2),
        entries: {
          // 9 h, late: 1
          'E10': worked(AttendanceStatus.present, '10:00', '19:00'),
          'E2': leave,
          // Lent from Accounts: 8 h 20 m rounds to 8 h 30 m: 1.0625
          'E3': worked(AttendanceStatus.present, '09:00', '17:20', guest: true),
        },
      ),
      AttendanceSheet(
        teamId: 'team-2',
        date: day(2),
        entries: {'E3': const AttendanceEntry.workingIn('team-1')},
      ),
      AttendanceSheet(
        teamId: 'team-1',
        date: day(16),
        entries: {
          // No out time: counts 0, flagged.
          'E10': worked(AttendanceStatus.present, '09:00', null),
          // 3 h 30 m half-day: 0.5625
          'E2': worked(AttendanceStatus.halfDay, '09:00', '12:30'),
        },
      ),
      // Next month: not in this report.
      AttendanceSheet(
        teamId: 'team-1',
        date: Day(month.next.year, month.next.month, 1),
        entries: {'E10': worked(AttendanceStatus.present, '08:00', '20:00')},
      ),
    ]);
  });

  AttendanceReport report([ReportPeriod? period]) => AttendanceReport(
    period: period ?? ReportPeriod.month(month),
    employees: repo.employees,
    rosters: repo.rosters,
    teamIds: repo.teams.map((t) => t.id),
    sheets: repo.sheets,
  );

  ReportRow rowOf(AttendanceReport r, String empId) =>
      r.rows.firstWhere((row) => row.employee.empId == empId);

  group('the report', () {
    test('counts each employee in the period only', () {
      final r = report();
      // Inactive Dev, with nothing marked, is left out.
      expect(r.rows.map((row) => row.employee.empId), ['E2', 'E3', 'E10']);

      final suraj = rowOf(r, 'E10');
      expect(suraj.summary.present, 3);
      expect(suraj.summary.late, 1);
      expect(suraj.dihadi, 2.5);
      expect(suraj.timesMissing, 1);
      expect(suraj.days.map((d) => d.date), [day(1), day(2), day(16)]);

      final bala = rowOf(r, 'E2');
      expect(bala.summary.absent, 1);
      expect(bala.summary.leave, 1);
      expect(bala.dihadi, 0.5625); // absent and leave earn nothing

      expect(r.dihadi, 2.5 + 0.5625 + 1.0625);
      expect(r.fileName, 'attendance-${month.key}.xlsx');
    });

    test('a lent worker counts once, in both teams', () {
      final chitra = rowOf(report(), 'E3');
      expect(chitra.daysRecorded, 1);
      expect(chitra.summary.present, 1);
      expect(chitra.dihadi, 1.0625);
      expect(chitra.teamIds, ['team-2', 'team-1']);
    });

    test('covers any dates', () {
      final half = ReportPeriod(day(1), day(15));
      expect(half.month, isNull);
      expect(
        half.label,
        '1 ${month.name.substring(0, 3)} ${month.year} – '
        '15 ${month.name.substring(0, 3)} ${month.year}',
      );
      final r = report(half);
      expect(rowOf(r, 'E10').dihadi, 2.5);
      expect(rowOf(r, 'E10').timesMissing, 0);
      expect(r.fileName, 'attendance-${day(1).key}_${day(15).key}.xlsx');
    });

    test('lists people on a team list even with nothing marked', () {
      repo.sheets.clear();
      final rows = report().rows;
      expect(rows.map((r) => r.employee.empId), ['E2', 'E3', 'E10']);
      expect(rows.every((r) => r.daysRecorded == 0 && r.dihadi == 0), isTrue);
    });
  });

  group('the Excel file', () {
    late Map<String, String> files;

    setUp(() {
      files = unzip(
        attendanceWorkbook(report(), {
          'team-1': 'Sector 122',
          'team-2': 'Accounts',
        }),
      );
    });

    String text(String t) => '<t xml:space="preserve">$t</t>';

    test('has a summary, all employees, and a tab each', () {
      final workbook = files['xl/workbook.xml']!;
      for (final name in [
        'Summary',
        'All employees',
        'E2 Bala, Jr.',
        'E3 Chitra',
        'E10 Suraj',
      ]) {
        expect(workbook, contains('name="$name"'));
      }
      expect(files.keys, contains('xl/worksheets/sheet5.xml'));
    });

    test('the summary has Dihadi, an empty rate to fill in, and totals', () {
      final sheet = files['xl/worksheets/sheet1.xml']!;
      // Suraj is the third employee: row 5.
      expect(sheet, contains('<c r="K5" s="5"><v>2.5</v></c>'));
      expect(sheet, contains('<c r="L5" s="6"/>'));
      expect(
        sheet,
        contains(
          '<c r="M5" s="6"><f>IF(L5=&quot;&quot;,&quot;&quot;,K5*L5)</f></c>',
        ),
      );
      expect(sheet, contains('<f>SUM(K3:K5)</f><v>4.125</v>'));
      expect(sheet, contains('<f>SUM(M3:M5)</f>'));
    });

    test("each block looks like the firm's sheet and takes the rate from the summary", () {
      final sheet = files['xl/worksheets/sheet5.xml']!; // E10 Suraj
      expect(sheet, contains(text('${month.label}  ·  Sector 122')));
      for (final h in ['Date', 'Name', 'In', 'Out', 'Time in hr', 'Dihadi']) {
        expect(sheet, contains(text(h)));
      }
      expect(sheet, contains(text('Suraj')));
      expect(sheet, contains(text(sheetDate(day(1)))));
      expect(sheet, contains(text('12:00')));
      // Day 1 is row 3: 1.5, Amount from Summary!L5, D*A = F3*G3.
      expect(sheet, contains('<c r="F3" s="5"><v>1.5</v></c>'));
      expect(sheet, contains("'Summary'!\$L\$5"));
      expect(sheet, contains('F3*G3'));
      expect(sheet, contains(text('Late')));
      expect(sheet, contains(text('Time missing')));
      // Yellow total under the three days.
      expect(sheet, contains('<f>SUM(F3:F5)</f><v>2.5</v>'));
      expect(sheet, contains('<f>SUM(H3:H5)</f>'));
      expect(sheet, contains('<mergeCell ref="A6:E6"/>'));
    });

    test('text is escaped and never a formula', () {
      final sheet = XlsxSheet('A/B: test')
        ..addRow([const XlsxCell('=1 & <b>')]);
      final out = unzip(buildXlsx([sheet]));
      expect(
        out['xl/worksheets/sheet1.xml'],
        contains(text('=1 &amp; &lt;b&gt;')),
      );
      expect(out['xl/workbook.xml'], contains('name="A B  test"'));
    });
  });

  test('Dihadi shows without trailing zeros', () {
    expect(dihadiText(18), '18');
    expect(dihadiText(1.0625), '1.0625');
  });

  group('the reports page', () {
    testWidgets("shows last month's Dihadi and shares it", (tester) async {
      tester.view
        ..physicalSize = const Size(400, 2000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? sharedName;
      Uint8List? sharedBytes;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReportsPage(
              repository: repo,
              share:
                  ({
                    required fileName,
                    required bytes,
                    required mimeType,
                    required subject,
                    origin,
                  }) async {
                    sharedName = fileName;
                    sharedBytes = bytes;
                  },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(month.label), findsOneWidget);
      expect(find.text('3 employees'), findsOneWidget);
      expect(find.text('4.125'), findsOneWidget);
      expect(find.text('Dihadi 2.5'), findsOneWidget);
      expect(find.text('Dihadi 1.0625'), findsOneWidget);
      expect(find.textContaining('rate'), findsOneWidget); // only the hint
      expect(find.textContaining('1 day has an in or out'), findsOneWidget);

      await tester.tap(find.text('Share as Excel file'));
      await tester.pumpAndSettle();
      expect(sharedName, 'attendance-${month.key}.xlsx');
      expect(unzip(sharedBytes!).keys, contains('xl/workbook.xml'));

      // The month before has nothing.
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing on these dates'), findsOneWidget);
      expect(find.text('Custom dates'), findsOneWidget);
    });
  });
}
