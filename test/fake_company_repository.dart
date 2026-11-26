import 'dart:async';

import 'package:daily_attendance/core/data/company_repository.dart';
import 'package:daily_attendance/core/models/app_user.dart';
import 'package:daily_attendance/core/models/company.dart';

/// In-memory [CompanyRepository] for tests.
class FakeCompanyRepository implements CompanyRepository {
  Company company = const Company(
    name: 'Acme',
    settings: CompanySettings.defaults,
  );
  final teams = <Team>[];
  final managers = <AppUser>[];

  /// Employees per team id; a team with any can't be deleted.
  final employeeCounts = <String, int>{};

  final _changes = StreamController<void>.broadcast();
  var _nextId = 1;

  void _changed() => _changes.add(null);

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  @override
  Stream<Company> watchCompany() => _watch(() => company);

  @override
  Stream<List<Team>> watchTeams() =>
      _watch(() => [...teams]..sort((a, b) => a.name.compareTo(b.name)));

  @override
  Stream<List<AppUser>> watchManagers() =>
      _watch(() => [...managers]..sort((a, b) => a.name.compareTo(b.name)));

  @override
  Future<void> addTeam(String name) async {
    teams.add(Team(id: 'team-${_nextId++}', name: name.trim()));
    _changed();
  }

  @override
  Future<void> renameTeam(String teamId, String name) async {
    final i = teams.indexWhere((t) => t.id == teamId);
    teams[i] = Team(id: teamId, name: name.trim());
    _changed();
  }

  @override
  Future<void> deleteTeam(String teamId) async {
    if ((employeeCounts[teamId] ?? 0) > 0) {
      throw const DataFailure(
        'This team still has employees. Move or remove them first.',
      );
    }
    teams.removeWhere((t) => t.id == teamId);
    for (var i = 0; i < managers.length; i++) {
      final m = managers[i];
      if (m.teamIds.contains(teamId)) {
        managers[i] = _copy(
          m,
          teamIds: m.teamIds.where((id) => id != teamId).toList(),
        );
      }
    }
    _changed();
  }

  @override
  Future<void> addManager({
    required String name,
    required String phone,
    required List<String> teamIds,
  }) async {
    if (managers.any((m) => m.phone == phone)) {
      throw const DataFailure('This number is already used in the app.');
    }
    managers.add(
      AppUser(
        phone: phone,
        companyId: 'company-1',
        role: UserRole.manager,
        name: name.trim(),
        teamIds: teamIds,
      ),
    );
    _changed();
  }

  @override
  Future<void> updateManager(
    String phone, {
    required String name,
    required List<String> teamIds,
    required bool active,
  }) async {
    final i = managers.indexWhere((m) => m.phone == phone);
    managers[i] = _copy(
      managers[i],
      name: name.trim(),
      teamIds: teamIds,
      active: active,
    );
    _changed();
  }

  @override
  Future<void> updateCompany({
    required String name,
    required CompanySettings settings,
  }) async {
    company = Company(name: name.trim(), settings: settings);
    _changed();
  }

  AppUser _copy(
    AppUser m, {
    String? name,
    List<String>? teamIds,
    bool? active,
  }) => AppUser(
    phone: m.phone,
    companyId: m.companyId,
    role: m.role,
    name: name ?? m.name,
    teamIds: teamIds ?? m.teamIds,
    active: active ?? m.active,
  );
}
