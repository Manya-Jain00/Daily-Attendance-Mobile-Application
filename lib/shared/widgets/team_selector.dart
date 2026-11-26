import 'package:material_ui/material_ui.dart';

import '../../core/models/company.dart';

/// Picks which of the supervisor's teams a screen shows. With one team there's
/// nothing to pick, so it just names that team.
class TeamSelector extends StatelessWidget {
  const TeamSelector({
    super.key,
    required this.teams,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Team> teams;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (teams.length == 1) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(
          children: [
            Icon(Icons.groups_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                teams.single.name,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          for (final team in teams)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(team.name),
                selected: team.id == selectedId,
                onSelected: (_) => onSelected(team.id),
              ),
            ),
        ],
      ),
    );
  }
}
