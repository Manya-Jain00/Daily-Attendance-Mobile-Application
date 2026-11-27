import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/employee_repository.dart';
import '../../shared/widgets/role_shell.dart';
import '../auth/auth_scope.dart';
import '../auth/auth_service.dart';
import 'attendance_page.dart';
import 'employees_page.dart';
import 'past_days_page.dart';
import '../../shared/widgets/role_names_scope.dart';

class SupervisorHomeScreen extends StatefulWidget {
  const SupervisorHomeScreen({super.key});

  @override
  State<SupervisorHomeScreen> createState() => _SupervisorHomeScreenState();
}

class _SupervisorHomeScreenState extends State<SupervisorHomeScreen> {
  EmployeeRepository? _repository;
  String? _openedFor;
  List<String> _openedTeams = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reopened when the director changes this supervisor's teams, so the team list
    // follows. Kept while signing out, so the pages don't flash empty.
    final session = AuthScope.of(context).session;
    if (session is SignedIn &&
        (session.user.phone != _openedFor ||
            !listEquals(session.user.teamIds, _openedTeams))) {
      _openedFor = session.user.phone;
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
          label: namesOf(context).employee.titles,
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
