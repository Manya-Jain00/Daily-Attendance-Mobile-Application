import 'dart:typed_data';

import '../models/attendance.dart';
import '../models/attendance_report.dart';
import '../models/role_names.dart';
import 'xlsx.dart';

/// The report as an Excel workbook, laid out like the firm's paper sheets:
///
/// 1. **Summary**: one line per employee with their Dihadi, an empty Daily
///    rate for the director to fill in, and Pay (Dihadi × rate); a yellow total.
/// 2. **All employees**: each employee's block one after another (title,
///    one row per day, yellow total), a printed page each.
/// 3. One tab per employee with just their block.
///
/// The app doesn't know rates. Each employee's rate is typed once on the
/// Summary tab; the Amount and D*A cells of their blocks pick it up from
/// there, and every total is a formula.
Uint8List attendanceWorkbook(
  AttendanceReport report,
  Map<String, String> teamNames, {
  RoleNames names = RoleNames.defaults,
}) {
  String teams(ReportRow row) =>
      row.teamIds.map((t) => teamNames[t] ?? 'A deleted team').join(', ');

  // Where each employee's rate is typed on the Summary tab.
  final rateCells = {
    for (var i = 0; i < report.rows.length; i++)
      report.rows[i].employee.empId:
          "'$_summaryName'!\$${columnName(_rateCol)}\$${_firstSummaryRow + i}",
  };

  final all = XlsxSheet(
    'All ${names.employee.words}',
    columnWidths: _blockWidths,
  );
  for (final row in report.rows) {
    final total = _addBlock(
      all,
      report.period,
      row,
      teams(row),
      rateCells[row.employee.empId]!,
    );
    all
      ..pageBreakAfter(total)
      ..addRow([]);
  }
  return buildXlsx([
    _summary(report, teams),
    all,
    for (final row in report.rows)
      _employeeSheet(
        report.period,
        row,
        teams(row),
        rateCells[row.employee.empId]!,
      ),
  ]);
}

const _summaryName = 'Summary';
const _firstSummaryRow = 3;
const _dihadiCol = 10, _rateCol = 11, _payCol = 12;

/// One employee's own tab, named after them.
XlsxSheet _employeeSheet(
  ReportPeriod period,
  ReportRow row,
  String teams,
  String rateCell,
) {
  final sheet = XlsxSheet(
    '${row.employee.empId} ${row.employee.name}',
    columnWidths: _blockWidths,
  )..freezeRows = 2;
  _addBlock(sheet, period, row, teams, rateCell);
  return sheet;
}

XlsxCell _text(Object? value, [XlsxStyle style = XlsxStyle.text]) =>
    XlsxCell(value, style: style);

/// `IF(rate="","",formula)`: stays empty until a rate is typed.
String _ifRate(String rate, String formula) => 'IF($rate="","",$formula)';

XlsxSheet _summary(AttendanceReport report, String Function(ReportRow) teams) {
  const header = [
    'Emp ID',
    'Name',
    'Designation',
    'Teams',
    'Present',
    'Half-days',
    'Absent',
    'Leave',
    'Late marks',
    'Hours worked',
    'Dihadi',
    'Daily rate',
    'Pay (D*A)',
    'Times missing',
    'Status',
  ];
  final sheet = XlsxSheet(_summaryName)
    ..freezeRows = 2
    ..filterRow = 2;
  final title = sheet.addRow([
    _text(
      'Attendance · ${report.period.label}  ·  '
      'Type each daily rate once; pay fills in everywhere',
      XlsxStyle.title,
    ),
    for (var i = 1; i < header.length; i++) _text(null, XlsxStyle.title),
  ], height: 24);
  sheet
    ..merge(title, 0, header.length - 1)
    ..addRow([for (final h in header) _text(h, XlsxStyle.header)]);
  assert(sheet.nextRow == _firstSummaryRow);
  for (final row in report.rows) {
    final r = sheet.nextRow;
    final s = row.summary;
    final rate = cellRef(_rateCol, r);
    sheet.addRow([
      _text(row.employee.empId),
      _text(row.employee.name, XlsxStyle.bold),
      _text(row.employee.designation),
      _text(teams(row)),
      XlsxCell(s.present, style: XlsxStyle.count),
      XlsxCell(s.halfDay, style: XlsxStyle.count),
      XlsxCell(s.absent, style: XlsxStyle.count),
      XlsxCell(s.leave, style: XlsxStyle.count),
      XlsxCell(s.late, style: XlsxStyle.count),
      _text(hoursAndMinutes(s.minutes), XlsxStyle.textRight),
      XlsxCell(row.dihadi, style: XlsxStyle.decimal),
      const XlsxCell(null, style: XlsxStyle.money),
      XlsxCell(
        null,
        style: XlsxStyle.money,
        formula: _ifRate(rate, '${cellRef(_dihadiCol, r)}*$rate'),
      ),
      XlsxCell(row.timesMissing, style: XlsxStyle.count),
      _text(row.employee.active ? 'Active' : 'No longer active'),
    ]);
  }
  final last = sheet.nextRow - 1;
  String sum(int col) =>
      'SUM(${cellRef(col, _firstSummaryRow)}:${cellRef(col, last)})';
  final totalRow = [
    for (var c = 0; c < header.length; c++) _text(null, XlsxStyle.totalBlank),
  ];
  totalRow[0] = _text('Total', XlsxStyle.totalLabel);
  totalRow[_dihadiCol] = XlsxCell(
    report.dihadi,
    style: XlsxStyle.totalDecimal,
    formula: sum(_dihadiCol),
  );
  totalRow[_payCol] = XlsxCell(
    0,
    style: XlsxStyle.totalMoney,
    formula: sum(_payCol),
  );
  final total = sheet.addRow(totalRow);
  sheet.merge(total, 0, _dihadiCol - 1);
  if (report.rows.isEmpty) sheet.filterRow = null;
  return sheet;
}

// Date, Name, In, Out, Time in hr, Dihadi, Amount, D*A, Note.
const _blockWidths = <int, double>{
  0: 12,
  1: 30,
  2: 8,
  3: 8,
  4: 11,
  5: 9,
  6: 10,
  7: 11,
  8: 26,
};

/// One employee's block: title, headings, a row per day and the yellow
/// total. Amount is the rate typed at [rateCell]. Returns the total row's
/// number.
int _addBlock(
  XlsxSheet sheet,
  ReportPeriod period,
  ReportRow row,
  String teams,
  String rateCell,
) {
  const width = 9;
  final title = sheet.addRow([
    _text(
      [period.label, if (teams.isNotEmpty) teams].join('  ·  '),
      XlsxStyle.title,
    ),
    for (var i = 1; i < width; i++) _text(null, XlsxStyle.title),
  ], height: 24);
  sheet
    ..merge(title, 0, width - 1)
    ..addRow([
      for (final h in const [
        'Date',
        'Name',
        'In',
        'Out',
        'Time in hr',
        'Dihadi',
        'Amount',
        'D*A',
        'Note',
      ])
        _text(h, XlsxStyle.header),
    ]);

  final first = sheet.nextRow;
  for (final day in row.days) {
    final r = sheet.nextRow;
    final worked = day.status.worked;
    final amount = cellRef(6, r);
    final notes = [
      if (!worked) day.status.label,
      if (day.status == AttendanceStatus.halfDay) 'Marked half-day',
      if (day.late) 'Late',
      if (day.timeMissing) 'Time missing',
      if (day.day.entries.length > 1) 'Worked in two teams',
    ];
    sheet.addRow([
      _text(sheetDate(day.date)),
      _text(row.employee.name, XlsxStyle.bold),
      _text(day.inTime, XlsxStyle.textRight),
      _text(day.outTime, XlsxStyle.textRight),
      _text(
        worked && day.minutes > 0 ? hoursAndMinutes(day.minutes) : null,
        XlsxStyle.textRight,
      ),
      XlsxCell(day.dihadi, style: XlsxStyle.decimal),
      XlsxCell(
        null,
        style: XlsxStyle.money,
        formula: _ifRate(rateCell, rateCell),
      ),
      XlsxCell(
        null,
        style: XlsxStyle.money,
        formula: _ifRate(amount, '${cellRef(5, r)}*$amount'),
      ),
      _text(notes.join(', ')),
    ]);
  }
  final last = sheet.nextRow - 1;
  String sum(int col) =>
      last < first ? '0' : 'SUM(${cellRef(col, first)}:${cellRef(col, last)})';
  final total = sheet.addRow([
    _text('Total', XlsxStyle.totalLabel),
    for (var i = 1; i < 5; i++) _text(null, XlsxStyle.totalBlank),
    XlsxCell(row.dihadi, style: XlsxStyle.totalDecimal, formula: sum(5)),
    _text(null, XlsxStyle.totalBlank),
    XlsxCell(0, style: XlsxStyle.totalMoney, formula: sum(7)),
    _text(null, XlsxStyle.totalBlank),
  ]);
  sheet.merge(total, 0, 4);
  return total;
}
