import 'package:material_ui/material_ui.dart';

import '../../core/data/company_repository.dart';
import '../../core/data/employee_repository.dart';
import '../../shared/widgets/role_shell.dart';
import '../auth/auth_scope.dart';
import '../auth/auth_service.dart';
import '../supervisor/employees_page.dart';
import 'dashboard_page.dart';
import 'people_page.dart';
import 'reports_page.dart';
import 'settings_page.dart';
import 'teams_page.dart';

class DirectorHomeScreen extends StatefulWidget {
  const DirectorHomeScreen({super.key});

  @override
  State<DirectorHomeScreen> createState() => _DirectorHomeScreenState();
}

class _DirectorHomeScreenState extends State<DirectorHomeScreen> {
  CompanyRepository? _repository;

  /// The same attendance data supervisors use, opened for the director, so the
  /// dashboard sees and corrects every team.
  EmployeeRepository? _attendance;
  String? _openedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Kept while signing out, so the pages don't flash empty on the way out.
    final session = AuthScope.of(context).session;
    if (session is SignedIn && session.user.phone != _openedFor) {
      _openedFor = session.user.phone;
      _repository = CompanyDataScope.of(context)(session.user);
      _attendance = EmployeeDataScope.of(context)(session.user);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    final attendance = _attendance;
    if (repository == null || attendance == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return RoleShell(
      tabs: [
        ShellTab(
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          page: DashboardPage(
            key: ObjectKey(attendance),
            repository: attendance,
          ),
        ),
        ShellTab(
          label: 'Teams',
          icon: Icons.groups_outlined,
          selectedIcon: Icons.groups,
          page: TeamsPage(repository: repository),
        ),
        ShellTab(
          label: 'Employees',
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          page: EmployeesPage(
            key: ObjectKey(attendance),
            repository: attendance,
          ),
        ),
        ShellTab(
          label: 'People',
          icon: Icons.badge_outlined,
          selectedIcon: Icons.badge,
          page: PeoplePage(repository: repository),
        ),
        ShellTab(
          label: 'Reports',
          icon: Icons.insert_chart_outlined,
          selectedIcon: Icons.insert_chart,
          page: ReportsPage(key: ObjectKey(attendance), repository: attendance),
        ),
        ShellTab(
          label: 'Settings',
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
          page: SettingsPage(repository: repository),
        ),
      ],
    );
  }
}
