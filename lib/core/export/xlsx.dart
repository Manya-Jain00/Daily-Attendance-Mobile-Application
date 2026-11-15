import 'dart:typed_data';

import 'package:archive/archive.dart';

/// How a cell looks. Every style but [plain] has thin borders, like a
/// printed register.
enum XlsxStyle {
  plain,

  /// Bold on light purple, centred: column headings.
  header,
  text,

  /// Text aligned right, e.g. times.
  textRight,
  bold,

  /// Up to 4 decimals, at least 2: 1.50, 1.0625.
  decimal,

  /// Rupees with thousands separators: 9,900.00.
  money,

  /// Whole number: 12.
  count,

  /// Large bold, centred: a block's title.
  title,

  /// Bold on yellow: the total row.
  totalLabel,
  totalDecimal,
  totalMoney,
  totalCount,

  /// Yellow, empty.
  totalBlank,
}

/// One cell: text (a [String]) or a number. With a [formula] (e.g.
/// `F3*G3`) Excel works the value out itself; [value] is what shows until it
/// does. Text is always text, so nothing typed into the app runs as a
/// formula.
class XlsxCell {
  const XlsxCell(this.value, {this.style = XlsxStyle.text, this.formula});

  final Object? value;
  final XlsxStyle style;
  final String? formula;
}

/// One tab of a workbook.
class XlsxSheet {
  XlsxSheet(this.name, {this.columnWidths = const {}});

  final String name;

  /// Column (0-based) to width in characters. Others fit their contents.
  final Map<int, double> columnWidths;

  final rows = <List<XlsxCell?>>[];
  final _merges = <String>[];
  final _breaks = <int>[];
  final _heights = <int, double>{};

  /// Rows (1-based) kept in view when scrolling.
  int freezeRows = 0;

  /// The heading row (1-based) to put filter buttons on, down to the last
  /// row.
  int? filterRow;

  /// Adds a row and returns its number (1-based), for formulas.
  int addRow(List<XlsxCell?> cells, {double? height}) {
    rows.add(cells);
    if (height != null) _heights[rows.length] = height;
    return rows.length;
  }

  /// The next row's number (1-based).
  int get nextRow => rows.length + 1;

  /// Joins columns [from] to [to] (0-based) of [row] into one cell.
  void merge(int row, int from, int to) =>
      _merges.add('${cellRef(from, row)}:${cellRef(to, row)}');

  /// Starts a new printed page after [row].
  void pageBreakAfter(int row) => _breaks.add(row);
}

/// `A1`-style reference for a 0-based [column] and 1-based [row].
String cellRef(int column, int row) => '${columnName(column)}$row';

/// 0 to A, 25 to Z, 26 to AA.
String columnName(int index) {
  var n = index + 1;
  var name = '';
  while (n > 0) {
    final rest = (n - 1) % 26;
    name = String.fromCharCode(65 + rest) + name;
    n = (n - 1) ~/ 26;
  }
  return name;
}

/// The MIME type of an `.xlsx` file.
const xlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// An Excel workbook (`.xlsx`) with [sheets] as its tabs, in order. Tabs
/// print landscape, one page wide.
Uint8List buildXlsx(List<XlsxSheet> sheets) {
  assert(sheets.isNotEmpty);
  final names = _uniqueNames([for (final s in sheets) s.name]);

  final archive = Archive()
    ..add(ArchiveFile.string('[Content_Types].xml', _contentTypes(sheets)))
    ..add(ArchiveFile.string('_rels/.rels', _rootRels))
    ..add(ArchiveFile.string('xl/workbook.xml', _workbook(sheets, names)))
    ..add(
      ArchiveFile.string('xl/_rels/workbook.xml.rels', _workbookRels(sheets)),
    )
    ..add(ArchiveFile.string('xl/styles.xml', _styles));
  for (var i = 0; i < sheets.length; i++) {
    archive.add(
      ArchiveFile.string('xl/worksheets/sheet${i + 1}.xml', _sheet(sheets[i])),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

int _width(List<XlsxCell?> row) => row.length;

int _lastColumn(XlsxSheet sheet) =>
    sheet.rows.fold(1, (m, r) => _width(r) > m ? _width(r) : m) - 1;

String _sheet(XlsxSheet sheet) {
  final lastCol = _lastColumn(sheet);
  final lastRow = sheet.rows.isEmpty ? 1 : sheet.rows.length;
  final out = StringBuffer()
    ..write(_xmlHead)
    ..write('<worksheet xmlns="$_main" xmlns:r="$_rel">')
    ..write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>')
    ..write('<dimension ref="A1:${cellRef(lastCol, lastRow)}"/>')
    ..write('<sheetViews><sheetView workbookViewId="0">');
  if (sheet.freezeRows > 0) {
    out.write(
      '<pane ySplit="${sheet.freezeRows}" '
      'topLeftCell="A${sheet.freezeRows + 1}" activePane="bottomLeft" '
      'state="frozen"/>',
    );
  }
  out
    ..write('</sheetView></sheetViews>')
    ..write('<sheetFormatPr defaultRowHeight="15"/>')
    ..write('<cols>');
  for (var c = 0; c <= lastCol; c++) {
    final width = sheet.columnWidths[c] ?? _fitWidth(sheet, c);
    out.write(
      '<col min="${c + 1}" max="${c + 1}" width="$width" customWidth="1"/>',
    );
  }
  out.write('</cols><sheetData>');
  for (var r = 0; r < sheet.rows.length; r++) {
    final number = r + 1;
    final height = sheet._heights[number];
    out.write(
      height == null
          ? '<row r="$number">'
          : '<row r="$number" ht="$height" customHeight="1">',
    );
    final cells = sheet.rows[r];
    for (var c = 0; c < cells.length; c++) {
      final cell = cells[c];
      if (cell != null) out.write(_cell(cellRef(c, number), cell));
    }
    out.write('</row>');
  }
  out.write('</sheetData>');
  if (sheet.filterRow case final row?) {
    out.write(
      '<autoFilter ref="${cellRef(0, row)}:${cellRef(lastCol, lastRow)}"/>',
    );
  }
  if (sheet._merges.isNotEmpty) {
    out.write('<mergeCells count="${sheet._merges.length}">');
    for (final m in sheet._merges) {
      out.write('<mergeCell ref="$m"/>');
    }
    out.write('</mergeCells>');
  }
  out
    ..write(
      '<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" '
      'header="0.3" footer="0.3"/>',
    )
    ..write(
      '<pageSetup paperSize="9" orientation="landscape" fitToWidth="1" '
      'fitToHeight="0"/>',
    );
  if (sheet._breaks.isNotEmpty) {
    out.write(
      '<rowBreaks count="${sheet._breaks.length}" '
      'manualBreakCount="${sheet._breaks.length}">',
    );
    for (final b in sheet._breaks) {
      out.write('<brk id="$b" max="16383" man="1"/>');
    }
    out.write('</rowBreaks>');
  }
  out.write('</worksheet>');
  return out.toString();
}

String _cell(String ref, XlsxCell cell) {
  final s = cell.style.index == 0 ? '' : ' s="${cell.style.index}"';
  final value = cell.value;
  final formula = cell.formula;
  if (formula != null) {
    final cached = value is num ? '<v>${_number(value)}</v>' : '';
    return '<c r="$ref"$s><f>${_escape(formula)}</f>$cached</c>';
  }
  if (value is num) return '<c r="$ref"$s><v>${_number(value)}</v></c>';
  final text = value == null ? '' : '$value';
  if (text.isEmpty) return '<c r="$ref"$s/>';
  return '<c r="$ref" t="inlineStr"$s><is>'
      '<t xml:space="preserve">${_escape(text)}</t></is></c>';
}

double _fitWidth(XlsxSheet sheet, int column) {
  var widest = 6;
  for (final row in sheet.rows) {
    if (column >= row.length) continue;
    final cell = row[column];
    if (cell == null || cell.style == XlsxStyle.title) continue;
    final value = cell.value;
    final length = switch (value) {
      null => 0,
      num() when cell.style == XlsxStyle.money =>
        value.toStringAsFixed(2).length + value.abs() ~/ 1000,
      num() => _number(value).length,
      _ => '$value'.length,
    };
    // Room for the filter button on headings.
    final extra = cell.style == XlsxStyle.header ? 3 : 0;
    if (length + extra > widest) widest = length + extra;
  }
  return (widest.clamp(6, 45) + 2).toDouble();
}

/// Plain digits, never `1e21` style.
String _number(num value) {
  if (value is int || value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(10).replaceFirst(RegExp(r'0+$'), '');
}

/// Excel allows 31 characters, none of `[]:*?/\`, and each name once.
List<String> _uniqueNames(List<String> wanted) {
  final used = <String>{};
  return [
    for (final name in wanted)
      () {
        var clean = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
        // A name can't start or end with an apostrophe.
        clean = clean.replaceAll(RegExp(r"^'+|'+$"), '').trim();
        if (clean.isEmpty) clean = 'Sheet';
        var candidate = _cut(clean, 31);
        for (var n = 2; used.contains(candidate.toLowerCase()); n++) {
          final suffix = ' ($n)';
          candidate = '${_cut(clean, 31 - suffix.length)}$suffix';
        }
        used.add(candidate.toLowerCase());
        return candidate;
      }(),
  ];
}

String _cut(String text, int max) =>
    text.length > max ? text.substring(0, max).trimRight() : text;

/// Escapes XML and drops characters XML can't hold at all.
String _escape(String text) => text
    .replaceAll(RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _workbook(List<XlsxSheet> sheets, List<String> names) {
  final out = StringBuffer()
    ..write('$_xmlHead<workbook xmlns="$_main" xmlns:r="$_rel"><sheets>');
  for (var i = 0; i < sheets.length; i++) {
    out.write(
      '<sheet name="${_escape(names[i])}" sheetId="${i + 1}" '
      'r:id="rId${i + 1}"/>',
    );
  }
  out.write('</sheets>');
  final filters = StringBuffer();
  for (var i = 0; i < sheets.length; i++) {
    final row = sheets[i].filterRow;
    if (row == null) continue;
    final quoted = "'${names[i].replaceAll("'", "''")}'";
    final lastCol = columnName(_lastColumn(sheets[i]));
    final lastRow = sheets[i].rows.length;
    filters.write(
      '<definedName name="_xlnm._FilterDatabase" localSheetId="$i" '
      'hidden="1">${_escape(quoted)}!\$A\$$row:\$$lastCol\$$lastRow'
      '</definedName>',
    );
  }
  if (filters.isNotEmpty) out.write('<definedNames>$filters</definedNames>');
  // Formulas are worked out again when the file is opened.
  out.write('<calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>');
  return out.toString();
}

const _xmlHead = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const _main = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

String _contentTypes(List<XlsxSheet> sheets) {
  final out = StringBuffer()
    ..write(
      '$_xmlHead<Types xmlns="http://schemas.openxmlformats.org/package/'
      '2006/content-types">'
      '<Default Extension="rels" ContentType="application/'
      'vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
    );
  for (var i = 0; i < sheets.length; i++) {
    out.write(
      '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
      'ContentType="application/'
      'vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
    );
  }
  out.write('</Types>');
  return out.toString();
}

const _rootRels =
    '$_xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/'
    'package/2006/relationships">'
    '<Relationship Id="rId1" Type="$_rel/officeDocument" '
    'Target="xl/workbook.xml"/></Relationships>';

String _workbookRels(List<XlsxSheet> sheets) {
  final out = StringBuffer()
    ..write(
      '$_xmlHead<Relationships xmlns="http://schemas.openxmlformats.org/'
      'package/2006/relationships">',
    );
  for (var i = 0; i < sheets.length; i++) {
    out.write(
      '<Relationship Id="rId${i + 1}" Type="$_rel/worksheet" '
      'Target="worksheets/sheet${i + 1}.xml"/>',
    );
  }
  out.write(
    '<Relationship Id="rId${sheets.length + 1}" Type="$_rel/styles" '
    'Target="styles.xml"/></Relationships>',
  );
  return out.toString();
}

/// Builds one `<xf>` (cell format); fonts 0 normal, 1 bold, 2 bold 14;
/// fills 2 purple, 3 yellow; border 1 thin.
String _xf({
  int numFmt = 0,
  int font = 0,
  int fill = 0,
  int border = 1,
  String? align,
}) {
  final attrs = StringBuffer(
    'numFmtId="$numFmt" fontId="$font" fillId="$fill" borderId="$border" '
    'xfId="0"',
  );
  if (numFmt != 0) attrs.write(' applyNumberFormat="1"');
  if (font != 0) attrs.write(' applyFont="1"');
  if (fill != 0) attrs.write(' applyFill="1"');
  if (border != 0) attrs.write(' applyBorder="1"');
  if (align == null) return '<xf $attrs/>';
  return '<xf $attrs applyAlignment="1"><alignment horizontal="$align" '
      'vertical="center"/></xf>';
}

/// In the order of [XlsxStyle].
final _cellFormats = [
  _xf(border: 0), // plain
  _xf(font: 1, fill: 2, align: 'center'), // header
  _xf(), // text
  _xf(align: 'right'), // textRight
  _xf(font: 1), // bold
  _xf(numFmt: 164), // decimal
  _xf(numFmt: 165), // money
  _xf(numFmt: 1), // count
  _xf(font: 2, align: 'center'), // title
  _xf(font: 1, fill: 3, align: 'center'), // totalLabel
  _xf(numFmt: 164, font: 1, fill: 3), // totalDecimal
  _xf(numFmt: 165, font: 1, fill: 3), // totalMoney
  _xf(numFmt: 1, font: 1, fill: 3), // totalCount
  _xf(fill: 3), // totalBlank
];

final _styles =
    '$_xmlHead<styleSheet xmlns="$_main">'
    '<numFmts count="2">'
    '<numFmt numFmtId="164" formatCode="0.00##"/>'
    '<numFmt numFmtId="165" formatCode="#,##0.00"/>'
    '</numFmts>'
    '<fonts count="3">'
    '<font><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
    '<font><b/><sz val="14"/><name val="Calibri"/><family val="2"/></font>'
    '</fonts>'
    '<fills count="4">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFE8E2FB"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFFFF00"/>'
    '<bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="2">'
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
    '<border><left style="thin"><color auto="1"/></left>'
    '<right style="thin"><color auto="1"/></right>'
    '<top style="thin"><color auto="1"/></top>'
    '<bottom style="thin"><color auto="1"/></bottom><diagonal/></border>'
    '</borders>'
    '<cellStyleXfs count="1">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="${_cellFormats.length}">${_cellFormats.join()}</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/>'
    '</cellStyles></styleSheet>';
