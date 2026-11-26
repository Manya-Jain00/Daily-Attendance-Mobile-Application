import 'package:material_ui/material_ui.dart';

import '../models/app_user.dart';
import '../models/company.dart';

/// Everything the director's setup screens read and change in their own company:
/// the company itself, its teams and its supervisors.
///
/// Streams update live. Methods throw [DataFailure] with a message that can
/// be shown as is.
abstract class CompanyRepository {
  Stream<Company> watchCompany();

  /// Sorted by name.
  Stream<List<Team>> watchTeams();

  /// Active and inactive supervisors, sorted by name.
  Stream<List<AppUser>> watchSupervisors();

  /// Active and inactive accountants, sorted by name.
  Stream<List<AppUser>> watchAccountants();

  Future<void> addTeam(String name);

  Future<void> renameTeam(String teamId, String name);

  /// Also takes the team off every supervisor who had it. Refused while the team
  /// still has employees.
  Future<void> deleteTeam(String teamId);

  /// Adds a supervisor by their mobile number ([phone], E.164). They can log in
  /// with it straight away, using a code sent by SMS. Refused if the number
  /// is already in the app, in this company or another.
  Future<void> addSupervisor({
    required String name,
    required String phone,
    required List<String> teamIds,
  });

  /// Changes a supervisor's name, teams or active state. The number can't
  /// change, because it's their login; add them again with the new number.
  Future<void> updateSupervisor(
    String phone, {
    required String name,
    required List<String> teamIds,
    required bool active,
  });

  /// Adds an accountant by their mobile number ([phone], E.164), the same way
  /// as [addSupervisor]. Accountants have no teams: they see every team, and
  /// can't change anything.
  Future<void> addAccountant({required String name, required String phone});

  /// Changes an accountant's name or active state.
  Future<void> updateAccountant(
    String phone, {
    required String name,
    required bool active,
  });

  Future<void> updateCompany({
    required String name,
    required CompanySettings settings,
  });
}

class DataFailure implements Exception {
  const DataFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Opens the [CompanyRepository] for a signed-in director (or an accountant,
/// who only reads it).
typedef CompanyRepositoryFactory = CompanyRepository Function(AppUser user);

/// Makes the [CompanyRepositoryFactory] available to every screen, so tests
/// can swap Firestore for an in-memory fake.
class CompanyDataScope extends InheritedWidget {
  const CompanyDataScope({super.key, required this.open, required super.child});

  final CompanyRepositoryFactory open;

  static CompanyRepositoryFactory of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<CompanyDataScope>();
    assert(scope != null, 'No CompanyDataScope above this widget');
    return scope!.open;
  }

  @override
  bool updateShouldNotify(CompanyDataScope oldWidget) => open != oldWidget.open;
}
