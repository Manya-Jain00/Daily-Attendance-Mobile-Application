import 'package:material_ui/material_ui.dart';

import '../models/app_user.dart';
import '../models/company.dart';

/// Everything the director's setup screens read and change in their own company:
/// the company itself, its teams and its managers.
///
/// Streams update live. Methods throw [DataFailure] with a message that can
/// be shown as is.
abstract class CompanyRepository {
  Stream<Company> watchCompany();

  /// Sorted by name.
  Stream<List<Team>> watchTeams();

  /// Active and inactive managers, sorted by name.
  Stream<List<AppUser>> watchManagers();

  Future<void> addTeam(String name);

  Future<void> renameTeam(String teamId, String name);

  /// Also takes the team off every manager who had it. Refused while the team
  /// still has employees.
  Future<void> deleteTeam(String teamId);

  /// Adds a manager by their mobile number ([phone], E.164). They can log in
  /// with it straight away, using a code sent by SMS. Refused if the number
  /// is already in the app, in this company or another.
  Future<void> addManager({
    required String name,
    required String phone,
    required List<String> teamIds,
  });

  /// Changes a manager's name, teams or active state. The number can't
  /// change, because it's their login; add them again with the new number.
  Future<void> updateManager(
    String phone, {
    required String name,
    required List<String> teamIds,
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

/// Opens the [CompanyRepository] for a signed-in director.
typedef CompanyRepositoryFactory = CompanyRepository Function(AppUser director);

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
