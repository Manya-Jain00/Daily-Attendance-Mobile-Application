import 'package:material_ui/material_ui.dart';

import '../../core/data/employee_repository.dart';
import '../../core/models/company.dart';
import '../../core/models/employee.dart';
import '../../core/models/month.dart';
import '../../core/models/roster.dart';
import '../../shared/widgets/load_state.dart';
import '../../shared/widgets/month_selector.dart';
import '../../shared/widgets/team_selector.dart';
import 'employee_form_page.dart';
import 'pick_employee_page.dart';

/// Manager: who works in each of their teams, month by month. Each month
/// starts as a copy of the month before, so the manager only adds or removes
/// the people who changed. The daily attendance sheet lists these people.
class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key, required this.repository});

  final EmployeeRepository repository;

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

enum _AddChoice { newEmployee, fromAnotherTeam }

class _EmployeesPageState extends State<EmployeesPage> {
  late final _teams = widget.repository.watchTeams();
  late final _employees = widget.repository.watchEmployees();

  /// This month can be changed, and next month planned ahead. Past months
  /// are view only (the CEO corrects those).
  final _thisMonth = Month.now();
  late Month _month = _thisMonth;
  late Stream<List<Roster>> _rosters = widget.repository.watchRosters(_month);

  /// The team on screen. Null until the teams load.
  String? _teamId;

  bool get _editable => _month == _thisMonth || _month == _thisMonth.next;

  void _showMonth(Month month) => setState(() {
    _month = month;
    _rosters = widget.repository.watchRosters(month);
  });

  /// Keeps the chosen team if it's still one of mine, or picks the first.
  String _selectedFrom(List<Team> myTeams) {
    final current = _teamId;
    if (current != null && myTeams.any((t) => t.id == current)) return current;
    return _teamId = myTeams.first.id;
  }

  Future<void> _add(_View view) async {
    final choice = await showModalBottomSheet<_AddChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('New employee'),
              subtitle: const Text('Someone not in the app yet'),
              onTap: () => Navigator.pop(context, _AddChoice.newEmployee),
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('From another team'),
              subtitle: const Text(
                'Someone already in the app who works in this team this '
                'month',
              ),
              onTap: () => Navigator.pop(context, _AddChoice.fromAnotherTeam),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => switch (choice) {
          _AddChoice.newEmployee => EmployeeFormPage(
            repository: widget.repository,
            list: view.list,
            allEmployees: view.employees,
          ),
          _AddChoice.fromAnotherTeam => PickEmployeePage(
            repository: widget.repository,
            list: view.list,
            allEmployees: view.employees,
            teamsOf: view.teamsOf,
          ),
        },
      ),
    );
  }

  void _edit(_View view, Employee employee) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmployeeFormPage(
          repository: widget.repository,
          list: view.list,
          allEmployees: view.employees,
          employee: employee,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Team>>(
      stream: _teams,
      builder: (context, teamsSnap) => StreamBuilder<List<Employee>>(
        stream: _employees,
        builder: (context, employeesSnap) => StreamBuilder<List<Roster>>(
          stream: _rosters,
          builder: (context, rostersSnap) {
            final loading = loadStateFor([teamsSnap, employeesSnap]);
            if (loading != null) return loading;
            final teams = teamsSnap.data!;
            final mine = widget.repository.myTeamIds;
            final myTeams = teams.where((t) => mine.contains(t.id)).toList();
            if (myTeams.isEmpty) {
              return const EmptyState(
                icon: Icons.groups_outlined,
                title: 'No teams yet',
                message:
                    'You have not been given a team yet. Ask your CEO to '
                    'assign you one, then add its employees here.',
              );
            }
            final teamId = _selectedFrom(myTeams);
            final rosters = rostersSnap.data;
            final view = rosters == null
                ? null
                : _View.of(
                    teams: teams,
                    employees: employeesSnap.data!,
                    rosters: rosters,
                    team: myTeams.firstWhere((t) => t.id == teamId),
                    month: _month,
                  );
            return Scaffold(
              backgroundColor: Colors.transparent,
              floatingActionButton: view != null && _editable
                  ? FloatingActionButton.extended(
                      heroTag: null,
                      onPressed: () => _add(view),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add employee'),
                    )
                  : null,
              body: Column(
                children: [
                  TeamSelector(
                    teams: myTeams,
                    selectedId: teamId,
                    onSelected: (id) => setState(() => _teamId = id),
                  ),
                  MonthSelector(
                    month: _month,
                    first: _thisMonth.minus(12),
                    last: _thisMonth.next,
                    onChanged: _showMonth,
                  ),
                  Expanded(
                    child: loadStateFor([rostersSnap]) ?? _buildList(view!),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(_View view) {
    final list = view.list;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    final notes = <Widget>[
      if (!_editable)
        const _Note(
          icon: Icons.lock_outline,
          text: 'A past month: view only. Ask your CEO to correct it.',
        )
      else if (list.copiedFrom != null && list.empIds.isNotEmpty)
        _Note(
          icon: Icons.content_copy_outlined,
          text:
              'Same people as ${list.copiedFrom!.label}. Add or remove '
              'anyone who has changed; the list is then saved for '
              '${_month.name}.',
        ),
    ];

    final people = view.people;
    if (people.isEmpty) {
      return Column(
        children: [
          ...notes.map(
            (n) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: n,
            ),
          ),
          Expanded(
            child: EmptyState(
              icon: Icons.people_outline,
              title: 'Nobody on the list',
              message: _editable
                  ? 'Add the people who work in ${list.team.name} in '
                        '${_month.name}. Next month starts with the same '
                        'people.'
                  : 'Nobody worked in ${list.team.name} in ${_month.label}.',
            ),
          ),
        ],
      );
    }

    // Active employees first; people who left stay listed so they can be
    // turned back on.
    final sorted = [
      ...people.where((e) => e.active),
      ...people.where((e) => !e.active),
    ];
    final activeCount = people.where((e) => e.active).length;
    final inactiveCount = people.length - activeCount;
    final header = <Widget>[
      ...notes,
      Text(
        [
          activeCount == 1 ? '1 employee' : '$activeCount employees',
          if (inactiveCount > 0) '$inactiveCount inactive',
        ].join(' · '),
        style: theme.textTheme.bodyMedium?.copyWith(color: muted),
      ),
    ];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
      itemCount: header.length + sorted.length,
      separatorBuilder: (_, i) => SizedBox(height: i < header.length ? 4 : 8),
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        final employee = sorted[i - header.length];
        final otherTeams = [
          for (final name in view.teamsOf[employee.empId] ?? const <String>[])
            if (name != list.team.name) name,
        ];
        return Card(
          child: ListTile(
            onTap: () => _edit(view, employee),
            leading: CircleAvatar(
              backgroundColor: employee.active
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              foregroundColor: employee.active
                  ? theme.colorScheme.onPrimaryContainer
                  : muted,
              child: Text(initialOf(employee.name)),
            ),
            title: Text(
              employee.name,
              style: employee.active ? null : TextStyle(color: muted),
            ),
            subtitle: Text(
              [
                [
                  employee.empId,
                  if (employee.designation.isNotEmpty) employee.designation,
                ].join(' · '),
                if (otherTeams.isNotEmpty) 'Also in ${otherTeams.join(', ')}',
              ].join('\n'),
            ),
            trailing: employee.active
                ? const Icon(Icons.chevron_right)
                : const Chip(
                    label: Text('Inactive'),
                    visualDensity: VisualDensity.compact,
                  ),
          ),
        );
      },
    );
  }
}

/// One team's list for one month, as the form pages need it.
class TeamList {
  const TeamList({
    required this.team,
    required this.month,
    required this.empIds,
    required this.editable,
    this.copiedFrom,
  });

  final Team team;
  final Month month;

  /// Who's on the list now (copied from [copiedFrom] if this month has no
  /// saved list of its own).
  final List<String> empIds;
  final bool editable;
  final Month? copiedFrom;

  bool contains(String empId) => empIds.contains(empId);
}

/// Everything the page shows for one team and month.
class _View {
  const _View({
    required this.list,
    required this.employees,
    required this.people,
    required this.teamsOf,
  });

  factory _View.of({
    required List<Team> teams,
    required List<Employee> employees,
    required List<Roster> rosters,
    required Team team,
    required Month month,
  }) {
    final now = Month.now();
    final effective = EffectiveRoster.of(rosters, team.id, month);
    final byId = {for (final e in employees) e.empId: e};
    // Which teams each person is on this month, for "Also in ...".
    final teamsOf = <String, List<String>>{};
    for (final t in teams) {
      for (final id in EffectiveRoster.of(rosters, t.id, month).empIds) {
        (teamsOf[id] ??= []).add(t.name);
      }
    }
    return _View(
      list: TeamList(
        team: team,
        month: month,
        empIds: effective.empIds,
        editable: month == now || month == now.next,
        copiedFrom: effective.copiedFrom,
      ),
      employees: employees,
      people: [for (final id in effective.empIds) ?byId[id]]
        ..sort(Employee.compareByEmpId),
      teamsOf: teamsOf,
    );
  }

  final TeamList list;
  final List<Employee> employees;

  /// The employees on [list], sorted by Emp ID.
  final List<Employee> people;

  /// Emp ID -> names of the teams they're on this month.
  final Map<String, List<String>> teamsOf;
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

String initialOf(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
}
