import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/app_constants.dart';
import 'core/data/company_repository.dart';
import 'core/data/employee_repository.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_scope.dart';
import 'features/auth/auth_service.dart';
import 'routing/app_router.dart';
import 'shared/widgets/role_names_scope.dart';

class DailyAttendanceApp extends StatefulWidget {
  const DailyAttendanceApp({
    super.key,
    required this.auth,
    required this.openCompany,
    required this.openEmployees,
  });

  /// Passed in so tests can use fakes instead of Firebase.
  final AuthService auth;
  final CompanyRepositoryFactory openCompany;
  final EmployeeRepositoryFactory openEmployees;

  @override
  State<DailyAttendanceApp> createState() => _DailyAttendanceAppState();
}

class _DailyAttendanceAppState extends State<DailyAttendanceApp> {
  late final GoRouter _router = createAppRouter(widget.auth);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      auth: widget.auth,
      child: CompanyDataScope(
        open: widget.openCompany,
        child: EmployeeDataScope(
          open: widget.openEmployees,
          child: MaterialApp.router(
            title: AppConstants.appName,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            routerConfig: _router,
            builder: (context, child) => RoleNamesHost(child: child!),
          ),
        ),
      ),
    );
  }
}
