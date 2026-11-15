import 'package:material_ui/material_ui.dart';

import '../../core/data/company_repository.dart';
import '../../core/models/app_user.dart';
import '../../core/models/company.dart';
import '../../shared/widgets/load_state.dart';
import 'manager_form_page.dart';

/// CEO: the company's managers, with their teams. Tap one to edit them.
class ManagersPage extends StatefulWidget {
  const ManagersPage({
    super.key,
    required this.repository,
    required this.companyCode,
  });

  final CompanyRepository repository;
  final String companyCode;

  @override
  State<ManagersPage> createState() => _ManagersPageState();
}

class _ManagersPageState extends State<ManagersPage> {
  late final _teams = widget.repository.watchTeams();
  late final _managers = widget.repository.watchManagers();

  void _open(List<Team> teams, List<AppUser> managers, [AppUser? manager]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ManagerFormPage(
          repository: widget.repository,
          companyCode: widget.companyCode,
          teams: teams,
          managers: managers,
          manager: manager,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Team>>(
      stream: _teams,
      builder: (context, teamsSnap) => StreamBuilder<List<AppUser>>(
        stream: _managers,
        builder: (context, managersSnap) {
          final loading = loadStateFor([teamsSnap, managersSnap]);
          final teams = teamsSnap.data;
          final managers = managersSnap.data;
          return Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: loading != null
                ? null
                : FloatingActionButton.extended(
                    heroTag: null,
                    onPressed: () => _open(teams!, managers!),
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                    label: const Text('Add manager'),
                  ),
            body: loading ?? _buildList(teams!, managers!),
          );
        },
      ),
    );
  }

  Widget _buildList(List<Team> teams, List<AppUser> managers) {
    if (managers.isEmpty) {
      return EmptyState(
        icon: Icons.badge_outlined,
        title: 'No managers yet',
        message: teams.isEmpty
            ? 'Add your teams first (Teams tab), then add managers here and '
                  'give each one a username and PIN to log in.'
            : 'Add managers and give each one a username and PIN to log in.',
      );
    }
    final teamNames = {for (final t in teams) t.id: t.name};
    // Active managers first; deactivated ones stay listed so they can be
    // turned back on.
    final sorted = [
      ...managers.where((m) => m.active),
      ...managers.where((m) => !m.active),
    ];
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final manager = sorted[i];
        final managedTeams = [for (final id in manager.teamIds) ?teamNames[id]];
        final muted = theme.colorScheme.onSurfaceVariant;
        return Card(
          child: ListTile(
            onTap: () => _open(teams, managers, manager),
            leading: CircleAvatar(
              backgroundColor: manager.active
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              foregroundColor: manager.active
                  ? theme.colorScheme.onPrimaryContainer
                  : muted,
              child: Text(_initial(manager.name)),
            ),
            title: Text(
              manager.name,
              style: manager.active ? null : TextStyle(color: muted),
            ),
            subtitle: Text(
              '${manager.username} · '
              '${managedTeams.isEmpty ? 'No teams' : managedTeams.join(', ')}',
            ),
            trailing: manager.active
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

String _initial(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
}
