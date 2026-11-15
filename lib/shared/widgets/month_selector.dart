import 'package:material_ui/material_ui.dart';

import '../../core/models/month.dart';

/// "‹ November 2026 ›": steps between months, from [first] to [last].
class MonthSelector extends StatelessWidget {
  const MonthSelector({
    super.key,
    required this.month,
    required this.first,
    required this.last,
    required this.onChanged,
  });

  final Month month;
  final Month first;
  final Month last;
  final ValueChanged<Month> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: month > first ? () => onChanged(month.previous) : null,
          ),
          Expanded(
            child: Text(
              month.label,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: month < last ? () => onChanged(month.next) : null,
          ),
        ],
      ),
    );
  }
}
