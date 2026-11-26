import 'package:material_ui/material_ui.dart';

import '../../core/data/employee_repository.dart';
import '../../core/models/attendance.dart';
import '../../core/models/company.dart';
import '../../core/models/day.dart';
import '../../core/models/employee.dart';
import '../../core/models/overview.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/brand_app_bar.dart';
import '../../shared/widgets/load_state.dart';
import '../supervisor/attendance_page.dart' show statusColor;
import '../supervisor/employees_page.dart' show initialOf;

/// Director: one employee's attendance over any dates, across every team they
/// worked in. First pick the person, then the dates.
class EmployeeHistoryPage extends StatefulWidget {
  const EmployeeHistoryPage({super.key, required this.repository});

  final EmployeeRepository repository;

  /// Longest range shown at once, so one look can't read years of sheets.
  static const maxDays = 366;

  @override
  State<EmployeeHistoryPage> createState() => _EmployeeHistoryPageState();
}

class _EmployeeHistoryPageState extends State<EmployeeHistoryPage> {
  EmployeeRepository get _repo => widget.repository;

  late final _teams = _repo.watchTeams();
  late final _employees = _repo.watchEmployees();
  final _search = TextEditingController();

  /// Null while picking someone.
  String? _empId;

  /// This month so far.
  late Day _from = Day(Day.today().year, Day.today().month, 1);
  late Day _to = Day.today();
  late Stream<List<AttendanceSheet>> _sheets = _repo.watchAttendance(
    _from,
    _to,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setRange(Day from, Day to) {
    if (to.daysSince(from) >= EmployeeHistoryPage.maxDays) {
      showMessage(
        context,
        'Pick at most ${EmployeeHistoryPage.maxDays} days at a time.',
      );
      return;
    }
    setState(() {
      _from = from;
      _to = to;
      _sheets = _repo.watchAttendance(from, to);
    });
  }

  Future<void> _pickRange() async {
    DateTime asDate(Day d) => DateTime(d.year, d.month, d.day);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: asDate(_from), end: asDate(_to)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Show attendance from … to',
    );
    if (picked != null && mounted) {
      _setRange(Day.of(picked.start), Day.of(picked.end));
    }
  }

  void _thisMonth() {
    final today = Day.today();
    _setRange(Day(today.year, today.month, 1), today);
  }

  void _lastMonth() {
    final month = Day.today().monthOf.previous;
    final first = Day(month.year, month.month, 1);
    _setRange(first, Day(month.next.year, month.next.month, 1).previous);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back from someone's history goes back to the list first.
      canPop: _empId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _empId = null);
      },
      child: Scaffold(
        appBar: const BrandAppBar(title: 'Employee history'),
        body: StreamBuilder<List<Team>>(
          stream: _teams,
          builder: (context, teamsSnap) => StreamBuilder<List<Employee>>(
            stream: _employees,
            builder: (context, employeesSnap) {
              final loading = loadStateFor([teamsSnap, employeesSnap]);
              if (loading != null) return loading;
              final employees = employeesSnap.data!;
              final employee = employees
                  .where((e) => e.empId == _empId)
                  .firstOrNull;
              if (employee == null) return _buildPicker(employees);
              return _buildHistory(employee, {
                for (final t in teamsSnap.data!) t.id: t.name,
              });
            },
          ),
        ),
      ),
    );
  }

  // ---- Picking someone ----------------------------------------------------

  Widget _buildPicker(List<Employee> employees) {
    final query = _search.text.trim().toLowerCase();
    final matches =
        [
          for (final e in employees)
            if (query.isEmpty ||
                e.name.toLowerCase().contains(query) ||
                e.empId.toLowerCase().contains(query))
              e,
        ]..sort((a, b) {
          // People who left go last.
          if (a.active != b.active) return a.active ? -1 : 1;
          return Employee.compareByEmpId(a, b);
        });
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search by name or Emp ID',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: matches.isEmpty
              ? EmptyState(
                  icon: Icons.person_search_outlined,
                  title: employees.isEmpty ? 'No employees yet' : 'No match',
                  message: employees.isEmpty
                      ? 'Supervisors add employees on their Employees tab.'
                      : 'Check the spelling of the name or Emp ID.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: matches.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final e = matches[i];
                    return Card(
                      child: ListTile(
                        onTap: () => setState(() => _empId = e.empId),
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          foregroundColor: theme.colorScheme.onPrimaryContainer,
                          child: Text(initialOf(e.name)),
                        ),
                        title: Text(e.name),
                        subtitle: Text(
                          [
                            e.empId,
                            if (e.designation.isNotEmpty) e.designation,
                            if (!e.active) 'No longer active',
                          ].join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---- One person's history -----------------------------------------------

  /// "Sun, 1 Nov – Sun, 15 Nov 2026".
  String get _rangeLabel {
    if (_from == _to) return _from.longLabel;
    final from = _from.year == _to.year ? _from.label : _from.longLabel;
    return '$from – ${_to.longLabel}';
  }

  Widget _buildHistory(Employee employee, Map<String, String> teamNames) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final header = <Widget>[
      Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: Text(initialOf(employee.name)),
          ),
          title: Text(employee.name),
          subtitle: Text(
            [
              employee.empId,
              if (employee.designation.isNotEmpty) employee.designation,
              if (!employee.active) 'No longer active',
            ].join(' · '),
          ),
          trailing: TextButton(
            onPressed: () => setState(() => _empId = null),
            child: const Text('Change'),
          ),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _pickRange,
        icon: const Icon(Icons.date_range_outlined),
        label: Text(_rangeLabel),
      ),
      Wrap(
        spacing: 8,
        children: [
          ActionChip(label: const Text('This month'), onPressed: _thisMonth),
          ActionChip(label: const Text('Last month'), onPressed: _lastMonth),
        ],
      ),
    ];

    return StreamBuilder<List<AttendanceSheet>>(
      stream: _sheets,
      builder: (context, sheetsSnap) {
        final loading = loadStateFor([sheetsSnap]);
        final days = loading == null
            ? historyOf(employee.empId, sheetsSnap.data!)
            : const <EmployeeDay>[];
        final items = <Widget>[
          ...header,
          const SizedBox(height: 8),
          if (loading != null)
            SizedBox(height: 240, child: loading)
          else if (days.isEmpty)
            const SizedBox(
              height: 240,
              child: EmptyState(
                icon: Icons.event_busy_outlined,
                title: 'Nothing recorded',
                message: 'No team marked them on these dates.',
              ),
            )
          else ...[
            _SummaryCard(summary: HistorySummary(days), days: days.length),
            const SizedBox(height: 4),
            Text(
              'Days with nothing recorded are not listed.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 4),
            for (final day in days) _DayCard(day: day, teamNames: teamNames),
          ],
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: items,
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.days});

  final HistorySummary summary;
  final int days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = summary;
    Widget count(String label, int value, Color color) => Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          FittedBox(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
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
                '$days ${days == 1 ? 'day' : 'days'} recorded',
                if (s.late > 0) '${s.late} late',
                if (s.minutes > 0) '${displayDuration(s.minutes)} worked',
              ].join(' · '),
              style: theme.textTheme.titleSmall,
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
          ],
        ),
      ),
    );
  }
}

/// One day: what each team recorded, with times and hours.
class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.teamNames});

  final EmployeeDay day;
  final Map<String, String> teamNames;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = day.status;
    final color = statusColor(status);
    final lines = [for (final e in day.entries) _describe(e)];
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          child: Text(
            status.letter,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        title: Text('${day.date.longLabel} · ${status.label}'),
        subtitle: Text(lines.join('\n')),
        trailing: day.late
            ? Text(
                'Late',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: const Color(0xFF8D6E00),
                ),
              )
            : null,
      ),
    );
  }

  String _describe(TeamEntry e) {
    final entry = e.entry;
    final team = teamNames[e.teamId] ?? 'A deleted team';
    final parts = [
      entry.guest ? '$team (lent for the day)' : team,
      if (day.entries.length > 1) entry.status.label,
      if (entry.status.worked)
        '${entry.inTime == null ? '--:--' : displayTime(entry.inTime!)} – '
            '${entry.outTime == null ? '--:--' : displayTime(entry.outTime!)}',
      if (entry.minutes != null) displayDuration(entry.minutes!),
    ];
    return parts.join(' · ');
  }
}
