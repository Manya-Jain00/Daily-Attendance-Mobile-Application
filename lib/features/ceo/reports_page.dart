import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/data/employee_repository.dart';
import '../../core/export/attendance_workbook.dart';
import '../../core/export/xlsx.dart';
import '../../core/models/attendance.dart';
import '../../core/models/attendance_report.dart';
import '../../core/models/company.dart';
import '../../core/models/day.dart';
import '../../core/models/employee.dart';
import '../../core/models/month.dart';
import '../../core/models/roster.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/load_state.dart';
import '../../shared/widgets/month_selector.dart';
import '../manager/employees_page.dart' show initialOf;

/// Hands a finished file to the phone's share sheet (WhatsApp, email,
/// Drive, …). [origin] is where the button is, for tablets.
typedef ShareFile = Future<void> Function({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
  required String subject,
  Rect? origin,
});

Future<void> shareWithPhone({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
  required String subject,
  Rect? origin,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: mimeType)],
      fileNameOverrides: [fileName],
      subject: subject,
      sharePositionOrigin: origin,
    ),
  );
}

/// 18.0 to "18", 1.0625 to "1.0625".
String dihadiText(double value) =>
    value.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');

/// CEO: every employee's attendance and Dihadi for a month (or any dates),
/// shared as an Excel file for payroll (the CEO adds rates there).
class ReportsPage extends StatefulWidget {
  const ReportsPage({
    super.key,
    required this.repository,
    this.share = shareWithPhone,
  });

  /// Opened for the CEO ([EmployeeRepository.isCeo]).
  final EmployeeRepository repository;

  final ShareFile share;

  /// Earliest month to step back to.
  static const firstMonth = Month(2020, 1);

  /// Longest custom period, so one report can't read years of sheets.
  static const maxDays = 366;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  EmployeeRepository get _repo => widget.repository;

  late final _teams = _repo.watchTeams();
  late final _employees = _repo.watchEmployees();

  /// Last month: by the time salaries are done, it's over.
  late ReportPeriod _period = ReportPeriod.month(Month.now().previous);
  late Stream<List<Roster>> _rosters;
  late Stream<List<AttendanceSheet>> _sheets;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _watch(_period);
  }

  void _watch(ReportPeriod period) {
    _period = period;
    // Lists for the period's last month reach back 12 months.
    _rosters = _repo.watchRosters(period.to.monthOf);
    _sheets = _repo.watchAttendance(period.from, period.to);
  }

  void _show(ReportPeriod period) => setState(() => _watch(period));

  Future<void> _pickDates() async {
    DateTime asDate(Day d) => DateTime(d.year, d.month, d.day);
    final today = Day.today();
    final end = _period.to > today ? today : _period.to;
    final start = _period.from > end ? end : _period.from;
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: asDate(start), end: asDate(end)),
      firstDate: DateTime(ReportsPage.firstMonth.year),
      lastDate: DateTime.now(),
      helpText: 'Report from … to',
    );
    if (picked == null || !mounted) return;
    final period = ReportPeriod(Day.of(picked.start), Day.of(picked.end));
    if (period.days > ReportsPage.maxDays) {
      showMessage(context, 'Pick at most ${ReportsPage.maxDays} days.');
      return;
    }
    _show(period);
  }

  Future<void> _share(
    AttendanceReport report,
    Map<String, String> teamNames,
    Rect? origin,
  ) async {
    setState(() => _sharing = true);
    try {
      await widget.share(
        fileName: report.fileName,
        bytes: attendanceWorkbook(report, teamNames),
        mimeType: xlsxMimeType,
        subject: 'Attendance, ${report.period.label}',
        origin: origin,
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Could not share the report: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Team>>(
      stream: _teams,
      builder: (context, teamsSnap) => StreamBuilder<List<Employee>>(
        stream: _employees,
        builder: (context, employeesSnap) => StreamBuilder<List<Roster>>(
          stream: _rosters,
          builder: (context, rostersSnap) =>
              StreamBuilder<List<AttendanceSheet>>(
                stream: _sheets,
                builder: (context, sheetsSnap) {
                  final loading = loadStateFor([
                    teamsSnap,
                    employeesSnap,
                    rostersSnap,
                    sheetsSnap,
                  ]);
                  final header = _PeriodBar(
                    period: _period,
                    onMonth: (m) => _show(ReportPeriod.month(m)),
                    onPickDates: _pickDates,
                  );
                  if (loading != null) {
                    return Column(
                      children: [
                        const SizedBox(height: 8),
                        header,
                        Expanded(child: loading),
                      ],
                    );
                  }
                  final teams = teamsSnap.data!;
                  final report = AttendanceReport(
                    period: _period,
                    employees: employeesSnap.data!,
                    rosters: rostersSnap.data!,
                    teamIds: teams.map((t) => t.id),
                    sheets: sheetsSnap.data!,
                  );
                  return _buildReport(header, report, {
                    for (final t in teams) t.id: t.name,
                  });
                },
              ),
        ),
      ),
    );
  }

  Widget _buildReport(
    Widget header,
    AttendanceReport report,
    Map<String, String> teamNames,
  ) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        header,
        if (report.rows.isEmpty)
          const SizedBox(
            height: 320,
            child: EmptyState(
              icon: Icons.insert_chart_outlined,
              title: 'Nothing on these dates',
              message:
                  'No employee was on a team list or marked by a team on '
                  'these dates.',
            ),
          )
        else ...[
          _TotalsCard(report: report),
          const SizedBox(height: 12),
          Builder(
            builder: (context) => FilledButton.icon(
              onPressed: _sharing
                  ? null
                  : () {
                      final box = context.findRenderObject() as RenderBox?;
                      final origin = box == null
                          ? null
                          : box.localToGlobal(Offset.zero) & box.size;
                      _share(report, teamNames, origin);
                    },
              icon: const Icon(Icons.ios_share),
              label: const Text('Share as Excel file'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Dihadi: 8 hours is 1 day, rounded to the nearest half hour. '
            'Days nobody marked are not counted. In the Excel file, type '
            "each person's daily rate once on the Summary tab and the pay "
            'fills in.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 4),
          for (final row in report.rows)
            _EmployeeCard(row: row, teamNames: teamNames),
        ],
      ],
    );
  }
}

/// Month arrows (or the custom dates) and the way to switch between them.
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.period,
    required this.onMonth,
    required this.onPickDates,
  });

  final ReportPeriod period;
  final ValueChanged<Month> onMonth;
  final VoidCallback onPickDates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = period.month;
    return Column(
      children: [
        if (month != null)
          MonthSelector(
            month: month,
            first: ReportsPage.firstMonth,
            last: Month.now(),
            onChanged: onMonth,
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              period.label,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            ActionChip(
              avatar: const Icon(Icons.date_range_outlined, size: 18),
              label: const Text('Custom dates'),
              onPressed: onPickDates,
            ),
            if (month == null)
              ActionChip(
                label: const Text('Back to months'),
                onPressed: () => onMonth(period.to.monthOf),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Everyone together: total Dihadi, and anything that needs a look.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.report});

  final AttendanceReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final people = report.rows.length;
    final missing = report.rows.fold(0, (n, r) => n + r.timesMissing);
    final warnings = [
      if (missing > 0)
        '$missing ${missing == 1 ? 'day has' : 'days have'} an in or out '
            'time missing, counted as 0.',
    ];
    Widget figure(String label, String value) => Expanded(
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                '$people ${people == 1 ? 'employee' : 'employees'}',
                if (report.period.contains(Day.today())) 'so far, up to today',
              ].join(' · '),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Row(children: [figure('Total Dihadi', dihadiText(report.dihadi))]),
            for (final w in warnings) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: AppColors.halfDay,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(w, style: theme.textTheme.bodySmall)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One employee over the period.
class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.row, required this.teamNames});

  final ReportRow row;
  final Map<String, String> teamNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final e = row.employee;
    final s = row.summary;
    final details = [
      e.empId,
      row.teamIds.map((t) => teamNames[t] ?? 'A deleted team').join(', '),
      if (!e.active) 'No longer active',
    ];
    final extras = [
      '${s.late} late',
      if (s.minutes > 0) '${displayDuration(s.minutes)} worked',
      if (row.daysRecorded == 0) 'nothing marked',
      if (row.timesMissing > 0) '${row.timesMissing} with a time missing',
    ];
    Widget count(String label, int value, Color color) => Expanded(
      child: Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(
              '$value',
              style: theme.textTheme.titleLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            FittedBox(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          ],
        ),
      ),
    );
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  child: Text(initialOf(e.name)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.name, style: theme.textTheme.titleMedium),
                      Text(
                        details.where((d) => d.isNotEmpty).join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                count('Present', s.present, AppColors.present),
                count('Half-day', s.halfDay, AppColors.halfDay),
                count('Absent', s.absent, AppColors.absent),
                count('Leave', s.leave, AppColors.leave),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Dihadi ${dihadiText(row.dihadi)}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              extras.join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
