import 'package:material_ui/material_ui.dart';

import '../../core/data/employee_repository.dart';
import '../../core/models/attendance.dart';
import '../../core/models/company.dart';
import '../../core/models/day.dart';
import '../../core/models/employee.dart';
import '../../core/models/overview.dart';
import '../../core/models/roster.dart';
import '../../core/models/team_day.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/load_state.dart';
import '../supervisor/attendance_page.dart';
import 'employee_history_page.dart';

/// Director: how every team's day is going (today, or any earlier day), and the
/// way into each team's full sheet and each employee's history.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.repository});

  /// Opened for the director ([EmployeeRepository.isDirector]) or an
  /// accountant ([EmployeeRepository.isAccountant]), who only views.
  final EmployeeRepository repository;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  EmployeeRepository get _repo => widget.repository;

  late final _teams = _repo.watchTeams();
  late final _employees = _repo.watchEmployees();

  /// Null while showing today, so the page moves on to the next day by
  /// itself.
  Day? _picked;
  late Day _date;
  late Stream<List<Roster>> _rosters;
  late Stream<List<AttendanceSheet>> _sheets;

  @override
  void initState() {
    super.initState();
    _watch(Day.today());
  }

  void _watch(Day date) {
    _date = date;
    _rosters = _repo.watchRosters(date.monthOf);
    _sheets = _repo.watchAttendance(date, date);
  }

  void _show(Day date) {
    final today = Day.today();
    if (date > today) return;
    setState(() {
      _picked = date == today ? null : date;
      _watch(date);
    });
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_date.year, _date.month, _date.day),
      firstDate: DateTime(2020),
      lastDate: today,
      helpText: 'Show attendance for',
    );
    if (picked != null && mounted) _show(Day.of(picked));
  }

  void _openTeam(String teamId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AttendancePage(repository: _repo, date: _date, teamId: teamId),
      ),
    );
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeHistoryPage(repository: _repo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_picked == null && Day.today() != _date) _watch(Day.today());
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
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      const SizedBox(height: 16),
                      _DateBar(
                        date: _date,
                        isToday: _picked == null,
                        onPrevious: () => _show(_date.previous),
                        onNext: () => _show(_date.next),
                        onPick: _pickDate,
                        onToday: () => _show(Day.today()),
                      ),
                      if (loading != null)
                        SizedBox(height: 320, child: loading)
                      else
                        ..._overview(
                          teams: teamsSnap.data!,
                          data: DayData(
                            date: _date,
                            sheets: sheetsSnap.data!,
                            rosters: rostersSnap.data!,
                            employees: employeesSnap.data!,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Card(
                        child: ListTile(
                          onTap: _openHistory,
                          leading: const Icon(Icons.manage_search),
                          title: const Text('Employee history'),
                          subtitle: const Text(
                            "One person's attendance over any dates",
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      ),
                    ],
                  );
                },
              ),
        ),
      ),
    );
  }

  List<Widget> _overview({required List<Team> teams, required DayData data}) {
    if (teams.isEmpty) {
      return [
        SizedBox(
          height: 280,
          child: EmptyState(
            icon: Icons.groups_outlined,
            title: 'No teams yet',
            message: _repo.isAccountant
                ? "The director has not added any teams yet. Each team's "
                      'attendance then shows here.'
                : 'Add teams and supervisors on the Teams and People tabs. '
                      "Each team's attendance then shows here.",
          ),
        ),
      ];
    }
    final rows = {for (final t in teams) t.id: data.rows(t.id)};
    final counts = {
      for (final t in teams) t.id: StatusCounts.ofRows(rows[t.id]!),
    };
    final withPeople = teams.where((t) => counts[t.id]!.total > 0).toList();
    final done = withPeople.where((t) => counts[t.id]!.done).length;
    return [
      _CompanyCard(
        counts: StatusCounts.ofCompany(rows.values),
        teamsDone: done,
        teamsWithPeople: withPeople.length,
      ),
      const SizedBox(height: 8),
      Text('Teams', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      for (final team in teams)
        _TeamCard(
          team: team,
          counts: counts[team.id]!,
          onTap: () => _openTeam(team.id),
        ),
    ];
  }
}

/// "‹ Sun, 15 Nov 2026 ›", tapping the date opens a calendar.
class _DateBar extends StatelessWidget {
  const _DateBar({
    required this.date,
    required this.isToday,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
    required this.onToday,
  });

  final Day date;
  final bool isToday;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrevious,
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                isToday ? 'Today · ${date.label}' : date.longLabel,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          if (isToday)
            const IconButton(
              tooltip: 'Next day',
              icon: Icon(Icons.chevron_right),
              onPressed: null,
            )
          else ...[
            IconButton(
              tooltip: 'Next day',
              icon: const Icon(Icons.chevron_right),
              onPressed: onNext,
            ),
            TextButton(onPressed: onToday, child: const Text('Today')),
          ],
        ],
      ),
    );
  }
}

/// The whole company's day, each person counted once.
class _CompanyCard extends StatelessWidget {
  const _CompanyCard({
    required this.counts,
    required this.teamsDone,
    required this.teamsWithPeople,
  });

  final StatusCounts counts;
  final int teamsDone;
  final int teamsWithPeople;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final notes = [
      '${counts.total} ${counts.total == 1 ? 'person' : 'people'}',
      '$teamsDone of $teamsWithPeople teams done',
      if (counts.late > 0) '${counts.late} late',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Whole company', style: theme.textTheme.titleMedium),
            Text(
              notes.join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Count('Present', counts.present, AppColors.present),
                _Count('Half-day', counts.halfDay, AppColors.halfDay),
                _Count('Absent', counts.absent, AppColors.absent),
                _Count('Leave', counts.leave, AppColors.leave),
                _Count('Pending', counts.pending, muted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        label: '$value $label',
        excludeSemantics: true,
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
      ),
    );
  }
}

/// One team: done or how many are still to be marked, and the counts.
class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.counts,
    required this.onTap,
  });

  final Team team;
  final StatusCounts counts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = counts;
    final String status;
    if (c.total == 0) {
      status = 'Nobody on the list';
    } else if (c.done) {
      status = 'Done';
    } else if (c.pending == c.total) {
      status = 'Not marked yet';
    } else {
      status = '${c.pending} of ${c.total} not marked';
    }
    final parts = [
      if (c.present > 0) '${c.present} present',
      if (c.halfDay > 0) '${c.halfDay} half-day',
      if (c.absent > 0) '${c.absent} absent',
      if (c.leave > 0) '${c.leave} leave',
      if (c.lentOut > 0) '${c.lentOut} in another team',
      if (c.late > 0) '${c.late} late',
    ];
    final ok = c.done;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          ok ? Icons.check_circle : Icons.schedule,
          color: ok ? AppColors.present : AppColors.halfDay,
        ),
        title: Text(team.name),
        subtitle: Text(
          [status, if (parts.isNotEmpty) parts.join(' · ')].join('\n'),
        ),
        isThreeLine: parts.isNotEmpty,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
