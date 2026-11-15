import 'package:material_ui/material_ui.dart';

import '../../core/app_constants.dart';
import '../../core/theme/app_colors.dart';

/// Purple-to-blue banner with the app name, used at the top of the login and
/// sign-up screens.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.compact = false, this.leading});

  /// Smaller version for screens with more fields to fit.
  final bool compact;

  /// Shown above the logo, e.g. a back button.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            compact ? 8 : 32,
            24,
            compact ? 20 : 32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ?leading,
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(compact ? 8 : 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.fact_check_outlined,
                      size: compact ? 28 : 36,
                      color: Colors.white,
                    ),
                  ),
                  if (compact) ...[
                    const SizedBox(width: 12),
                    Text(
                      AppConstants.appName,
                      style: textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
              if (!compact) ...[
                const SizedBox(height: 16),
                Text(
                  AppConstants.appName,
                  style: textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppConstants.tagline,
                  style: textTheme.bodyLarge?.copyWith(color: Colors.white70),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
