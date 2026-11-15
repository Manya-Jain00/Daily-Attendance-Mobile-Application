import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_colors.dart';

/// App bar with the purple-to-blue brand gradient.
class BrandAppBar extends StatelessWidget implements PreferredSizeWidget {
  const BrandAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      backgroundColor: AppColors.purple,
      foregroundColor: Colors.white,
      // Container (not DecoratedBox) so the gradient fills the whole bar.
      flexibleSpace: Container(
        decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      ),
      actions: actions,
    );
  }
}
