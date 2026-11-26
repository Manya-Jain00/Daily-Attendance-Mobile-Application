import 'package:material_ui/material_ui.dart';

import '../../core/data/company_repository.dart';
import '../../core/data/employee_repository.dart';
import '../../core/models/employee.dart';
import '../../shared/widgets/brand_app_bar.dart';
import '../../shared/widgets/load_state.dart';
import 'employees_page.dart';

/// Put someone already in the company on a team's monthly list. This is how
/// a manager adds people to their teams: only the director creates new
/// employees.
class PickEmployeePage extends StatefulWidget {
  const PickEmployeePage({
    super.key,
    required this.repository,
    required this.list,
    required this.allEmployees,
    required this.teamsOf,
  });

  final EmployeeRepository repository;
  final TeamList list;
  final List<Employee> allEmployees;

  /// Emp ID -> names of the teams they're on that month.
  final Map<String, List<String>> teamsOf;

  @override
  State<PickEmployeePage> createState() => _PickEmployeePageState();
}

class _PickEmployeePageState extends State<PickEmployeePage> {
  final _search = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pick(Employee employee) async {
    if (_busy) return;
    final list = widget.list;
    final team = list.team.name;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${employee.name} to $team?'),
        content: Text(
          'They go on $team\'s list from ${list.month.label}. If they are '
          'on other teams\' lists too, they stay there; each team marks its '
          'own attendance for them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.saveRoster(list.team.id, list.month, [
        ...list.empIds,
        employee.empId,
      ]);
      if (!mounted) return;
      showMessage(context, '${employee.name} added to $team');
      Navigator.pop(context);
    } on DataFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final candidates = [
      for (final e in widget.allEmployees)
        if (e.active &&
            !widget.list.contains(e.empId) &&
            (query.isEmpty ||
                e.name.toLowerCase().contains(query) ||
                e.empId.toLowerCase().contains(query)))
          e,
    ];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: BrandAppBar(title: 'Add to ${widget.list.team.name}'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _search,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search by name or Emp ID',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: candidates.isEmpty
                ? EmptyState(
                    icon: Icons.person_search_outlined,
                    title: query.isEmpty ? 'Nobody to add' : 'No match',
                    message: switch ((
                      query.isEmpty,
                      widget.repository.isDirector,
                    )) {
                      (true, true) =>
                        'Everyone in the company is already on this list.',
                      (true, false) =>
                        'Everyone in the company is already on this list. '
                            'Ask your director to add anyone new.',
                      (false, true) =>
                        'Check the spelling, or add them as a new employee.',
                      (false, false) =>
                        'Check the spelling. Someone new is added by your '
                            'director.',
                    },
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: candidates.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final e = candidates[i];
                      final teams = widget.teamsOf[e.empId];
                      return Card(
                        child: ListTile(
                          onTap: _busy ? null : () => _pick(e),
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            foregroundColor:
                                theme.colorScheme.onPrimaryContainer,
                            child: Text(initialOf(e.name)),
                          ),
                          title: Text(e.name),
                          subtitle: Text(
                            [
                              [
                                e.empId,
                                if (e.designation.isNotEmpty) e.designation,
                              ].join(' · '),
                              teams == null || teams.isEmpty
                                  ? 'Not on any team this month'
                                  : 'In ${teams.join(', ')}',
                            ].join('\n'),
                          ),
                          trailing: const Icon(Icons.add),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
