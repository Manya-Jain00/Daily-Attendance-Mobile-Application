import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';

/// What to show instead of a page's content while its data is loading or
/// failed to load, or null once the data is there.
Widget? loadStateFor(List<AsyncSnapshot<Object?>> snapshots) {
  for (final snapshot in snapshots) {
    if (snapshot.hasError) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load',
        message: '${snapshot.error}',
      );
    }
  }
  if (snapshots.any((s) => !s.hasData)) {
    return const Center(child: CircularProgressIndicator());
  }
  return null;
}

/// Centered icon, title and hint, for an empty list or an error.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.brandGradient,
              ),
              child: Icon(icon, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
