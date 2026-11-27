import 'package:material_ui/material_ui.dart';

import '../../core/data/employee_repository.dart';
import '../../core/models/attendance.dart';
import '../../core/models/company.dart';
import '../../core/models/day.dart';
import '../../core/models/employee.dart';
import '../../core/models/roster.dart';
import '../../core/models/team_day.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/load_state.dart';
import 'attendance_page.dart';
import '../../shared/widgets/role_names_scope.dart';

/// Supervisor: the days before today that can still be corrected, with how far
/// each team's sheet got. Tapping a team opens that day's sheet.
class PastDaysPage extends StatefulWidget {
  const PastDaysPage({super.key, required this.repository});

  final EmployeeRepository repository;

  @override
  State<PastDaysPage> createState() => _PastDaysPageState();
}

class _PastDaysPageState extends State<PastDaysPage> {
  EmployeeRepository get _repo => widget.repository;

  late final _teams = _repo.watchTeams();
  late final _employees = _repo.watchEmployees();
  late final _settings = _repo.watchSettings();

  late Day _today;
  late Stream<List<Roster>> _rosters;
  late Stream<List<AttendanceSheet>> _sheets;

  @override
  void initState() {
    super.initState();
    _watchFrom(Day.today());
  }

  /// Watches as far back as the edit window can ever reach, so changing it
  /// in Settings shows straight away.
  void _watchFrom(Day today) {
    _today = today;
    _rosters = _repo.watchRosters(today.monthOf);
    _sheets = _repo.watchAttendance(
      today.addDays(-CompanySettings.maxSupervisorEditDays),
      today.previous,
    );
  }

  void _open(Day date, String teamId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AttendancePage(repository: _repo, date: date, teamId: teamId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Day.today() != _today) _watchFrom(Day.today());
    return StreamBuilder<List<Team>>(
      stream: _teams,
      builder: (context, teamsSnap) => StreamBuilder<List<Employee>>(
        stream: _employees,
        builder: (context, employeesSnap) => StreamBuilder<CompanySettings>(
          stream: _settings,
          builder: (context, settingsSnap) => StreamBuilder<List<Roster>>(
            stream: _rosters,
            builder: (context, rostersSnap) =>
                StreamBuilder<List<AttendanceSheet>>(
                  stream: _sheets,
                  builder: (context, sheetsSnap) {
                    final loading = loadStateFor([
                      teamsSnap,
                      employeesSnap,
                      settingsSnap,
                      rostersSnap,
                      sheetsSnap,
                    ]);
                    if (loading != null) return loading;
                    return _buildList(
                      teams: teamsSnap.data!,
                      employees: employeesSnap.data!,
                      settings: settingsSnap.data!,
                      rosters: rostersSnap.data!,
                      sheets: sheetsSnap.data!,
                    );
                  },
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildList({
    required List<Team> teams,
    required List<Employee> employees,
    required CompanySettings settings,
    required List<Roster> rosters,
    required List<AttendanceSheet> sheets,
  }) {
    final mine = _repo.myTeamIds;
    final myTeams = teams.where((t) => mine.contains(t.id)).toList();
    if (myTeams.isEmpty) {
      return EmptyState(
        icon: Icons.groups_outlined,
        title: 'No teams yet',
        message:
            'You have not been given a team yet. Ask your ${namesOf(context).director.word} to '
            'assign you one.',
      );
    }
    final editDays = settings.supervisorEditDays;
    if (editDays == 0) {
      return EmptyState(
        icon: Icons.lock_outline,
        title: 'Only today can be marked',
        message:
            'Your ${namesOf(context).director.word} corrects earlier days.',
      );
    }
    final days = [for (var i = 1; i <= editDays; i++) _today.addDays(-i)];
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          'You can correct the last $editDays '
          '${editDays == 1 ? 'day' : 'days'}. Older days: ask your '
          '${namesOf(context).director.word}.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final date in days)
          _DayCard(
            date: date,
            teams: myTeams,
            data: DayData(
              date: date,
              sheets: sheets,
              rosters: rosters,
              employees: employees,
            ),
            onOpen: (teamId) => _open(date, teamId),
          ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.date,
    required this.teams,
    required this.data,
    required this.onOpen,
  });

  final Day date;
  final List<Team> teams;
  final DayData data;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(date.longLabel, style: theme.textTheme.titleMedium),
          ),
          for (final team in teams)
            _teamTile(context, team, data.progress(team.id)),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _teamTile(BuildContext context, Team team, SheetProgress p) {
    final String status;
    if (p.total == 0) {
      status = 'Nobody on the list';
    } else if (p.done) {
      status = 'Done · ${p.total} marked';
    } else if (p.marked == 0) {
      status = 'Not marked';
    } else {
      status = '${p.pending} of ${p.total} not marked';
    }
    return ListTile(
      dense: true,
      onTap: () => onOpen(team.id),
      leading: Icon(
        p.done ? Icons.check_circle : Icons.schedule,
        color: p.done ? AppColors.present : AppColors.halfDay,
      ),
      title: Text(team.name),
      subtitle: Text(status),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
