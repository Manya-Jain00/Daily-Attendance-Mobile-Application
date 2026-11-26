import 'package:material_ui/material_ui.dart';

import '../../core/data/company_repository.dart';
import '../../core/models/app_user.dart';
import '../../core/models/company.dart';
import '../../core/phone_number.dart';
import '../../shared/widgets/load_state.dart';
import 'supervisor_form_page.dart';

/// Director's People tab: everyone who logs in besides the director. The
/// company's supervisors, with their teams, and its accountants (view-only
/// logins), each in their own section. Tap one to edit them.
class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key, required this.repository});

  final CompanyRepository repository;

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  late final _teams = widget.repository.watchTeams();
  late final _supervisors = widget.repository.watchSupervisors();
  late final _accountants = widget.repository.watchAccountants();

  void _open(
    List<Team> teams,
    List<AppUser> people, {
    AppUser? person,
    UserRole role = UserRole.supervisor,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupervisorFormPage(
          repository: widget.repository,
          teams: teams,
          people: people,
          supervisor: person,
          role: person?.role ?? role,
        ),
      ),
    );
  }

  /// Asks whether to add a supervisor or an accountant.
  Future<void> _add(List<Team> teams, List<AppUser> people) async {
    final role = await showModalBottomSheet<UserRole>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Supervisor'),
              subtitle: const Text('Marks attendance for their teams'),
              onTap: () => Navigator.pop(context, UserRole.supervisor),
            ),
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Accountant'),
              subtitle: const Text(
                'Sees the dashboard, teams and reports. View only',
              ),
              onTap: () => Navigator.pop(context, UserRole.accountant),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (role == null || !mounted) return;
    _open(teams, people, role: role);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Team>>(
      stream: _teams,
      builder: (context, teamsSnap) => StreamBuilder<List<AppUser>>(
        stream: _supervisors,
        builder: (context, supervisorsSnap) => StreamBuilder<List<AppUser>>(
          stream: _accountants,
          builder: (context, accountantsSnap) {
            final loading = loadStateFor([
              teamsSnap,
              supervisorsSnap,
              accountantsSnap,
            ]);
            final teams = teamsSnap.data;
            final people = loading != null
                ? const <AppUser>[]
                : [...supervisorsSnap.data!, ...accountantsSnap.data!];
            return Scaffold(
              backgroundColor: Colors.transparent,
              floatingActionButton: loading != null
                  ? null
                  : FloatingActionButton.extended(
                      heroTag: null,
                      onPressed: () => _add(teams!, people),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add'),
                    ),
              body:
                  loading ??
                  _buildList(
                    teams!,
                    supervisorsSnap.data!,
                    accountantsSnap.data!,
                    people,
                  ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(
    List<Team> teams,
    List<AppUser> supervisors,
    List<AppUser> accountants,
    List<AppUser> people,
  ) {
    if (people.isEmpty) {
      return EmptyState(
        icon: Icons.badge_outlined,
        title: 'No one added yet',
        message: teams.isEmpty
            ? 'Add your teams first (Teams tab), then add supervisors and '
                  'accountants here by their mobile number. They log in with it.'
            : 'Add supervisors and accountants by their mobile number. They '
                  'log in with it.',
      );
    }
    final teamNames = {for (final t in teams) t.id: t.name};
    // Active people first; deactivated ones stay listed so they can be
    // turned back on.
    List<AppUser> activeFirst(List<AppUser> list) => [
      ...list.where((m) => m.active),
      ...list.where((m) => !m.active),
    ];
    String teamsOf(AppUser supervisor) {
      final names = [for (final id in supervisor.teamIds) ?teamNames[id]];
      return names.isEmpty ? 'No teams' : names.join(', ');
    }

    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    final items = <Widget>[
      heading('Supervisors'),
      if (supervisors.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'No supervisors yet.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      for (final supervisor in activeFirst(supervisors))
        _PersonCard(
          person: supervisor,
          detail: teamsOf(supervisor),
          onTap: () => _open(teams, people, person: supervisor),
        ),
      if (accountants.isNotEmpty) ...[
        heading('Accountants'),
        for (final accountant in activeFirst(accountants))
          _PersonCard(
            person: accountant,
            detail: 'View only',
            onTap: () => _open(teams, people, person: accountant),
          ),
      ],
    ];
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => items[i],
    );
  }
}

/// One supervisor or accountant: name, number and [detail].
class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.detail,
    required this.onTap,
  });

  final AppUser person;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: person.active
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          foregroundColor: person.active
              ? theme.colorScheme.onPrimaryContainer
              : muted,
          child: Text(_initial(person.name)),
        ),
        title: Text(
          person.name,
          style: person.active ? null : TextStyle(color: muted),
        ),
        subtitle: Text('${PhoneNumber.format(person.phone)} · $detail'),
        trailing: person.active
            ? const Icon(Icons.chevron_right)
            : const Chip(
                label: Text('Inactive'),
                visualDensity: VisualDensity.compact,
              ),
      ),
    );
  }
}

String _initial(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
}
