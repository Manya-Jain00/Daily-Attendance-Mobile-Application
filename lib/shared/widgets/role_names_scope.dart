import 'package:material_ui/material_ui.dart';

import '../../core/data/employee_repository.dart';
import '../../core/models/role_names.dart';
import '../../features/auth/auth_scope.dart';
import '../../features/auth/auth_service.dart';

/// What the signed-in person's company calls its roles. Defaults when
/// nobody is signed in, or outside the app (e.g. a page tested on its own).
RoleNames namesOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<RoleNamesScope>()?.names ??
    RoleNames.defaults;

class RoleNamesScope extends InheritedWidget {
  const RoleNamesScope({super.key, required this.names, required super.child});

  final RoleNames names;

  @override
  bool updateShouldNotify(RoleNamesScope oldWidget) => names != oldWidget.names;
}

/// Follows the signed-in company's role names live, for every screen
/// (including pages pushed on top of the home screens). Sits between the
/// data scopes and the navigator.
class RoleNamesHost extends StatefulWidget {
  const RoleNamesHost({super.key, required this.child});

  final Widget child;

  @override
  State<RoleNamesHost> createState() => _RoleNamesHostState();
}

class _RoleNamesHostState extends State<RoleNamesHost> {
  Stream<RoleNames>? _names;
  String? _openedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = AuthScope.of(context).session;
    final phone = session is SignedIn ? session.user.phone : null;
    if (phone == _openedFor) return;
    _openedFor = phone;
    _names = session is SignedIn
        ? EmployeeDataScope.of(context)(session.user)
              .watchSettings()
              .map((s) => s.roleNames)
              .distinct()
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final names = _names;
    if (names == null) {
      return RoleNamesScope(names: RoleNames.defaults, child: widget.child);
    }
    return StreamBuilder<RoleNames>(
      stream: names,
      builder: (context, snap) => RoleNamesScope(
        // Errors (e.g. offline): the defaults, rather than blocking the app.
        names: snap.data ?? RoleNames.defaults,
        child: widget.child,
      ),
    );
  }
}
