import 'package:material_ui/material_ui.dart';

import '../../features/auth/auth_scope.dart';
import 'brand_app_bar.dart';

class ShellTab {
  const ShellTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

/// Home layout shared by the director and manager areas: gradient app bar,
/// bottom navigation, and a log-out button.
class RoleShell extends StatefulWidget {
  const RoleShell({super.key, required this.tabs});

  final List<ShellTab> tabs;

  @override
  State<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<RoleShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tabs = widget.tabs;
    return Scaffold(
      appBar: BrandAppBar(
        title: tabs[_index].label,
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            // The router moves to the login screen once signed out.
            onPressed: () => AuthScope.of(context).signOut(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [for (final tab in tabs) tab.page],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
