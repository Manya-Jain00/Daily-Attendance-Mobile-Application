import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../auth/auth_scope.dart';
import '../auth/auth_service.dart';

/// Shows the company's login code, which the CEO gives to managers.
class CompanyCodeCard extends StatelessWidget {
  const CompanyCodeCard({
    super.key,
    this.margin = const EdgeInsets.fromLTRB(16, 16, 16, 0),
  });

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final session = AuthScope.of(context).session;
    final code = session is SignedIn ? session.user.companyCode : '';
    if (code.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Card(
      margin: margin,
      child: ListTile(
        leading: const Icon(Icons.apartment_outlined),
        title: Text(
          code,
          style: theme.textTheme.titleLarge?.copyWith(
            letterSpacing: 4,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: const Text('Company code: managers type this to log in'),
        trailing: IconButton(
          tooltip: 'Copy code',
          icon: const Icon(Icons.copy_outlined),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: code));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Company code copied')),
              );
            }
          },
        ),
      ),
    );
  }
}
