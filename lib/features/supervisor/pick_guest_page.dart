import 'package:material_ui/material_ui.dart';

import '../../core/models/employee.dart';
import '../../shared/widgets/brand_app_bar.dart';
import '../../shared/widgets/load_state.dart';
import '../../shared/widgets/person_avatar.dart';
import '../../shared/widgets/role_names_scope.dart';

/// Supervisor: pick someone from another team who works in this team for just
/// one day. They go on that day's sheet only, not on the monthly list, and
/// show as absent on their own team's sheet. Pops the chosen [Employee].
class PickGuestPage extends StatefulWidget {
  const PickGuestPage({
    super.key,
    required this.teamName,
    required this.candidates,
    required this.notes,
  });

  final String teamName;

  /// Active employees not on the sheet yet.
  final List<Employee> candidates;

  /// Emp ID -> their teams and what they're marked as elsewhere today.
  final Map<String, String> notes;

  @override
  State<PickGuestPage> createState() => _PickGuestPageState();
}

class _PickGuestPageState extends State<PickGuestPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final matches = [
      for (final e in widget.candidates)
        if (query.isEmpty ||
            e.name.toLowerCase().contains(query) ||
            e.empId.toLowerCase().contains(query))
          e,
    ];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: BrandAppBar(title: 'Working in ${widget.teamName} today'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'For one day only. They are marked present here and show as '
              'absent on their own team\'s sheet. To move someone for the '
              'whole month, use the ${namesOf(context).employee.titles} tab.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
                    title: query.isEmpty ? 'Nobody to add' : 'No match',
                    message: query.isEmpty
                        ? 'Everyone in the company is already on this sheet.'
                        : 'Check the spelling. New people are added on the '
                              '${namesOf(context).employee.titles} tab.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final e = matches[i];
                      return Card(
                        child: ListTile(
                          onTap: () => Navigator.pop(context, e),
                          leading: PersonAvatar(
                            name: e.name,
                            photo: e.photo,
                            enlargeOnTap: false,
                          ),
                          title: Text(e.name),
                          subtitle: Text(
                            [
                              [
                                e.empId,
                                if (e.designation.isNotEmpty) e.designation,
                              ].join(' · '),
                              widget.notes[e.empId] ??
                                  'Not on any team this month',
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
