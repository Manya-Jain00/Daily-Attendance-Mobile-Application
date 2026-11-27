import 'package:material_ui/material_ui.dart';

import '../../features/auth/auth_scope.dart';
import '../../features/auth/auth_service.dart';
import '../../features/profile/profile_page.dart';
import 'brand_app_bar.dart';
import 'person_avatar.dart';

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

/// Home layout shared by the director and supervisor areas: gradient app bar,
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
    final session = AuthScope.of(context).session;
    final me = session is SignedIn ? session.user : null;
    return Scaffold(
      appBar: BrandAppBar(
        title: tabs[_index].label,
        actions: [
          IconButton(
            tooltip: 'My profile',
            icon: me?.photo == null
                ? const Icon(Icons.account_circle_outlined)
                : PersonAvatar(
                    name: me!.name,
                    photo: me.photo,
                    radius: 14,
                    enlargeOnTap: false,
                  ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
            ),
          ),
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
