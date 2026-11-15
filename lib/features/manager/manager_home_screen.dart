import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/employee_repository.dart';
import '../../shared/widgets/role_shell.dart';
import '../auth/auth_scope.dart';
import '../auth/auth_service.dart';
import 'attendance_page.dart';
import 'employees_page.dart';
import 'past_days_page.dart';

class ManagerHomeScreen extends StatefulWidget {
  const ManagerHomeScreen({super.key});

  @override
  State<ManagerHomeScreen> createState() => _ManagerHomeScreenState();
}

class _ManagerHomeScreenState extends State<ManagerHomeScreen> {
  EmployeeRepository? _repository;
  String? _openedFor;
  List<String> _openedTeams = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reopened when the CEO changes this manager's teams, so the team list
    // follows. Kept while signing out, so the pages don't flash empty.
    final session = AuthScope.of(context).session;
    if (session is SignedIn &&
        (session.user.uid != _openedFor ||
            !listEquals(session.user.teamIds, _openedTeams))) {
      _openedFor = session.user.uid;
      _openedTeams = session.user.teamIds;
      _repository = EmployeeDataScope.of(context)(session.user);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = _repository;
    if (repository == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return RoleShell(
      tabs: [
        ShellTab(
          label: 'Today',
          icon: Icons.today_outlined,
          selectedIcon: Icons.today,
          page: AttendancePage(
            key: ObjectKey(repository),
            repository: repository,
          ),
        ),
        ShellTab(
          label: 'Employees',
          icon: Icons.people_outline,
          selectedIcon: Icons.people,
          // Keyed by the repository so a new team list starts fresh.
          page: EmployeesPage(
            key: ObjectKey(repository),
            repository: repository,
          ),
        ),
        ShellTab(
          label: 'Past days',
          icon: Icons.event_note_outlined,
          selectedIcon: Icons.event_note,
          page: PastDaysPage(
            key: ObjectKey(repository),
            repository: repository,
          ),
        ),
      ],
    );
  }
}
