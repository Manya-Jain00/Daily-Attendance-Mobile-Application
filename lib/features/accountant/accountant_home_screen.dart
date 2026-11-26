import 'package:material_ui/material_ui.dart';

import '../../core/data/company_repository.dart';
import '../../core/data/employee_repository.dart';
import '../../shared/widgets/role_shell.dart';
import '../auth/auth_scope.dart';
import '../auth/auth_service.dart';
import '../director/dashboard_page.dart';
import '../director/reports_page.dart';
import '../director/teams_page.dart';

/// Accountant: the director's Dashboard, Teams and Reports (with employee
/// history and the Excel export), view only. There is nothing to save: the
/// team sheets open locked, and the Teams tab has no add, rename or delete.
class AccountantHomeScreen extends StatefulWidget {
  const AccountantHomeScreen({super.key});

  @override
  State<AccountantHomeScreen> createState() => _AccountantHomeScreenState();
}

class _AccountantHomeScreenState extends State<AccountantHomeScreen> {
  CompanyRepository? _repository;
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
          page: TeamsPage(repository: repository, readOnly: true),
        ),
        ShellTab(
          label: 'Reports',
          icon: Icons.insert_chart_outlined,
          selectedIcon: Icons.insert_chart,
          page: ReportsPage(key: ObjectKey(attendance), repository: attendance),
        ),
      ],
    );
  }
}
