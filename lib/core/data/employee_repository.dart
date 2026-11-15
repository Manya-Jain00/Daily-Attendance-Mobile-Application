import 'package:material_ui/material_ui.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/company.dart';
import '../models/day.dart';
import '../models/employee.dart';
import '../models/month.dart';
import '../models/roster.dart';

/// What a manager reads and changes: the company's teams, its employees,
/// each team's monthly list of people and the daily attendance. The CEO's
/// dashboard opens one too, and then sees and corrects every team.
///
/// Every manager can see the whole staff list (to put someone from another
/// team on their own list), but can only change *their own* teams' lists.
///
/// Streams update live. Methods throw [DataFailure] (from
/// `company_repository.dart`) with a message that can be shown as is.
abstract class EmployeeRepository {
  /// The teams this manager looks after.
  List<String> get myTeamIds;

  /// Opened for the CEO: every team is theirs, and any day up to today can
  /// be corrected (no edit window).
  bool get isCeo;

  /// Every team in the company, sorted by name.
  Stream<List<Team>> watchTeams();

  /// Every employee in the company, active and inactive, sorted by Emp ID.
  Stream<List<Employee>> watchEmployees();

  /// Every team's saved lists from [month] and the 12 months before it,
  /// which is enough to work out each team's list for [month] (see
  /// [EffectiveRoster]).
  Stream<List<Roster>> watchRosters(Month month);

  /// Adds a new employee and puts them on [teamId]'s list for [month], which
  /// then holds [listEmpIds] plus them. Refused if the Emp ID is already
  /// used anywhere in the company.
  Future<void> addEmployee({
    required String empId,
    required String name,
    required String designation,
    required String teamId,
    required Month month,
    required List<String> listEmpIds,
  });

  /// The Emp ID can't change: it's the record's key, and attendance refers
  /// to it.
  Future<void> updateEmployee(
    String empId, {
    required String name,
    required String designation,
    required bool active,
  });

  /// Saves [teamId]'s list for [month].
  Future<void> saveRoster(String teamId, Month month, List<String> empIds);

  /// The company's office rules (late cutoff, half-day hours, edit window).
  Stream<CompanySettings> watchSettings();

  /// Every team's attendance sheets from [from] to [to], both included.
  /// Everyone's teams are needed to see who was lent to another team.
  Stream<List<AttendanceSheet>> watchAttendance(Day from, Day to);

  /// Saves [teamId]'s sheet for [date], replacing what was there.
  Future<void> saveAttendance(
    String teamId,
    Day date,
    Map<String, AttendanceEntry> entries,
  );
}

/// Opens the [EmployeeRepository] for a signed-in manager.
typedef EmployeeRepositoryFactory = EmployeeRepository Function(AppUser user);

/// Makes the [EmployeeRepositoryFactory] available to every screen, so tests
/// can swap Firestore for an in-memory fake.
class EmployeeDataScope extends InheritedWidget {
  const EmployeeDataScope({
    super.key,
    required this.open,
    required super.child,
  });

  final EmployeeRepositoryFactory open;

  static EmployeeRepositoryFactory of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<EmployeeDataScope>();
    assert(scope != null, 'No EmployeeDataScope above this widget');
    return scope!.open;
  }

  @override
  bool updateShouldNotify(EmployeeDataScope oldWidget) =>
      open != oldWidget.open;
}
