import 'package:material_ui/material_ui.dart';

import '../models/app_user.dart';
import '../models/company.dart';

/// Everything the CEO's setup screens read and change in their own company:
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

  /// Creates the manager's login (company code + [username] + [pin]) and
  /// their profile.
  Future<void> addManager({
    required String name,
    required String username,
    required String pin,
    required List<String> teamIds,
  });

  /// Changes a manager's name, teams or active state. The username can't
  /// change, because it's part of their login.
  Future<void> updateManager(
    String uid, {
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

/// Opens the [CompanyRepository] for a signed-in CEO.
typedef CompanyRepositoryFactory = CompanyRepository Function(AppUser ceo);

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
