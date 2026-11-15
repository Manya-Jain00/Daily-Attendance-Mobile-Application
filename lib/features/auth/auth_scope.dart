import 'package:material_ui/material_ui.dart';

import 'auth_service.dart';

/// Makes the [AuthService] available to every screen, and rebuilds the
/// widgets that read it when the session changes.
class AuthScope extends InheritedNotifier<AuthService> {
  const AuthScope({super.key, required AuthService auth, required super.child})
    : super(notifier: auth);

  static AuthService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AuthScope>();
    assert(scope != null, 'No AuthScope above this widget');
    return scope!.notifier!;
  }
}
