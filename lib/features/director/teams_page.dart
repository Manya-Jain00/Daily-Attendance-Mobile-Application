import 'package:material_ui/material_ui.dart';

import '../../core/data/company_repository.dart';
import '../../core/models/app_user.dart';
import '../../core/models/company.dart';
import '../../shared/widgets/load_state.dart';
import '../auth/form_validators.dart';

/// Director: create, rename and delete teams, and see who manages each one.
class TeamsPage extends StatefulWidget {
  const TeamsPage({super.key, required this.repository});

  final CompanyRepository repository;

  @override
  State<TeamsPage> createState() => _TeamsPageState();
}

enum _TeamAction { rename, delete }

class _TeamsPageState extends State<TeamsPage> {
  late final _teams = widget.repository.watchTeams();
  late final _managers = widget.repository.watchManagers();

  Future<void> _add(List<Team> teams) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TeamNameDialog(existing: teams),
    );
    if (name == null || !mounted) return;
    await _run(() => widget.repository.addTeam(name), 'Team "$name" added');
  }

  Future<void> _rename(Team team, List<Team> teams) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => TeamNameDialog(existing: teams, team: team),
    );
    if (name == null || name == team.name || !mounted) return;
    await _run(
      () => widget.repository.renameTeam(team.id, name),
      'Team renamed to "$name"',
    );
  }

  Future<void> _delete(Team team, List<AppUser> managers) async {
    final managerCount = managers
        .where((m) => m.teamIds.contains(team.id))
        .length;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${team.name}"?'),
        content: Text(
          managerCount == 0
              ? 'This cannot be undone.'
              : 'Its ${managerCount == 1 ? 'manager' : '$managerCount managers'} '
                    'will no longer be assigned to it. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              minimumSize: const Size(64, 40),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _run(
      () => widget.repository.deleteTeam(team.id),
      'Team "${team.name}" deleted',
    );
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showMessage(context, done);
    } on DataFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Team>>(
      stream: _teams,
      builder: (context, teamsSnap) => StreamBuilder<List<AppUser>>(
        stream: _managers,
        builder: (context, managersSnap) {
          final teams = teamsSnap.data;
          return Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: teams == null
                ? null
                : FloatingActionButton.extended(
                    heroTag: null,
                    onPressed: () => _add(teams),
                    icon: const Icon(Icons.add),
                    label: const Text('Add team'),
                  ),
            body:
                loadStateFor([teamsSnap, managersSnap]) ??
                _buildList(teams!, managersSnap.data!),
          );
        },
      ),
    );
  }

  Widget _buildList(List<Team> teams, List<AppUser> managers) {
    if (teams.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_outlined,
        title: 'No teams yet',
        message:
            'Add your teams, such as Marketing, Finance or Legal. Then add '
            'managers and assign them to teams.',
      );
    }
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: teams.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final team = teams[i];
        final names = [
          for (final m in managers)
            if (m.active && m.teamIds.contains(team.id)) m.name,
        ];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.groups_outlined,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            title: Text(team.name),
            subtitle: Text(
              names.isEmpty ? 'No manager yet' : names.join(', '),
              style: names.isEmpty
                  ? TextStyle(color: theme.colorScheme.error)
                  : null,
            ),
            trailing: PopupMenuButton<_TeamAction>(
              tooltip: 'Options for ${team.name}',
              onSelected: (action) => switch (action) {
                _TeamAction.rename => _rename(team, teams),
                _TeamAction.delete => _delete(team, managers),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _TeamAction.rename,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Rename'),
                  ),
                ),
                PopupMenuItem(
                  value: _TeamAction.delete,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Asks for a team name, refusing one that another team already has.
/// Returns the trimmed name, or null if cancelled.
class TeamNameDialog extends StatefulWidget {
  const TeamNameDialog({super.key, required this.existing, this.team});

  final List<Team> existing;

  /// The team being renamed, or null when adding one.
  final Team? team;

  @override
  State<TeamNameDialog> createState() => _TeamNameDialogState();
}

class _TeamNameDialogState extends State<TeamNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.team?.name);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final problem = validateName('Enter the team name')(value);
    if (problem != null) return problem;
    final name = value!.trim().toLowerCase();
    final taken = widget.existing.any(
      (t) => t.id != widget.team?.id && t.name.trim().toLowerCase() == name,
    );
    return taken ? 'There is already a team with this name' : null;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final adding = widget.team == null;
    return AlertDialog(
      title: Text(adding ? 'Add team' : 'Rename team'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          validator: _validate,
          onFieldSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            labelText: 'Team name',
            hintText: 'e.g. Marketing',
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: _submit,
          child: Text(adding ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
