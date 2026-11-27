import 'dart:async';
import 'dart:typed_data';

import 'package:daily_attendance/core/data/company_repository.dart';
import 'package:daily_attendance/core/data/employee_repository.dart';
import 'package:daily_attendance/core/location/location_service.dart';
import 'package:daily_attendance/core/models/attendance.dart';
import 'package:daily_attendance/core/models/company.dart';
import 'package:daily_attendance/core/models/day.dart';
import 'package:daily_attendance/core/models/employee.dart';
import 'package:daily_attendance/core/models/geo.dart';
import 'package:daily_attendance/core/models/month.dart';
import 'package:daily_attendance/core/models/roster.dart';

/// In-memory [EmployeeRepository] for tests. [teams] are the whole
/// company's; [myTeamIds] are the supervisor's own.
class FakeEmployeeRepository implements EmployeeRepository {
  final teams = <Team>[];
  final employees = <Employee>[];
  final rosters = <Roster>[];

  @override
  List<String> myTeamIds = [];

  @override
  bool isDirector = false;

  @override
  bool isAccountant = false;

  @override
  final FakeLocationService location = FakeLocationService();

  /// Who saves, for the stamps.
  String phone = '+919800000001';
  String name = 'Sunita';

  /// The location each save was given, in order.
  final savedLocations = <EntryLocation?>[];

  final _changes = StreamController<void>.broadcast();

  void _changed() => _changes.add(null);

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  /// The saved list for [teamId] in [month], or null if none was saved.
  List<String>? savedList(String teamId, Month month) => rosters
      .where((r) => r.teamId == teamId && r.month == month)
      .firstOrNull
      ?.empIds;

  @override
  Stream<List<Team>> watchTeams() =>
      _watch(() => [...teams]..sort((a, b) => a.name.compareTo(b.name)));

  @override
  Stream<List<Employee>> watchEmployees() =>
      _watch(() => [...employees]..sort(Employee.compareByEmpId));

  @override
  Stream<List<Roster>> watchRosters(Month month) => _watch(
    () => [
      for (final r in rosters)
        if (!(r.month > month) && !(r.month < month.minus(12))) r,
    ],
  );

  @override
  Future<void> addEmployee({
    required String empId,
    required String name,
    required String designation,
    required String teamId,
    required Month month,
    required List<String> listEmpIds,
  }) async {
    final id = Employee.normalizeEmpId(empId);
    if (employees.any((e) => e.empId == id)) {
      throw DataFailure('Emp ID $id is already used.');
    }
    employees.add(
      Employee(empId: id, name: name.trim(), designation: designation.trim()),
    );
    _save(teamId, month, [...listEmpIds, id]);
  }

  @override
  Future<void> updateEmployee(
    String empId, {
    required String name,
    required String designation,
    required bool active,
  }) async {
    final i = employees.indexWhere((e) => e.empId == empId);
    employees[i] = Employee(
      empId: empId,
      name: name.trim(),
      designation: designation.trim(),
      active: active,
      photo: employees[i].photo,
    );
    _changed();
  }

  @override
  Future<void> setEmployeePhoto(String empId, Uint8List? photo) async {
    final i = employees.indexWhere((e) => e.empId == empId);
    employees[i] = employees[i].withPhoto(photo);
    _changed();
  }

  @override
  Future<void> saveRoster(
    String teamId,
    Month month,
    List<String> empIds,
  ) async => _save(teamId, month, empIds);

  CompanySettings settings = CompanySettings.defaults;
  final sheets = <AttendanceSheet>[];

  /// The saved sheet for [teamId] on [date], or null.
  AttendanceSheet? savedSheet(String teamId, Day date) =>
      sheets.where((s) => s.teamId == teamId && s.date == date).firstOrNull;

  /// Set to make the next [saveAttendance] fail with this message.
  String? failNextSave;

  @override
  Stream<CompanySettings> watchSettings() => _watch(() => settings);

  @override
  Stream<List<AttendanceSheet>> watchAttendance(Day from, Day to) => _watch(
    () => [
      for (final s in sheets)
        if (!(s.date < from) && !(s.date > to)) s,
    ],
  );

  @override
  Future<void> saveAttendance(
    String teamId,
    Day date,
    Map<String, AttendanceEntry> entries, {
    EntryLocation? location,
  }) async {
    if (failNextSave case final message?) {
      failNextSave = null;
      throw DataFailure(message);
    }
    savedLocations.add(location);
    final now = DateTime(2026, 11, 27, 9, 42);
    entries = {
      for (final e in entries.entries)
        e.key: e.value.stamp == null
            ? e.value.withStamp(
                EntryStamp(
                  byPhone: phone,
                  byName: name,
                  at: now,
                  location: location,
                ),
              )
            : e.value,
    };
    sheets
      ..removeWhere((s) => s.teamId == teamId && s.date == date)
      ..add(
        AttendanceSheet(
          teamId: teamId,
          date: date,
          entries: {...entries},
          markedBy: 'supervisor-1',
        ),
      );
    _changed();
  }

  void _save(String teamId, Month month, List<String> empIds) {
    rosters
      ..removeWhere((r) => r.teamId == teamId && r.month == month)
      ..add(
        Roster(teamId: teamId, month: month, empIds: empIds.toSet().toList()),
      );
    _changed();
  }
}

/// [LocationService] for tests: answers with [result], or with
/// [afterPermission] once permission is asked for and [allow] is true.
class FakeLocationService implements LocationService {
  static const office = EntryLocation(
    point: GeoPoint(28.6139, 77.2090),
    accuracy: 12,
  );

  LocationResult result = const Located(office);
  LocationResult afterPermission = const Located(office);
  bool allow = true;

  int permissionRequests = 0;
  int locationSettingsOpened = 0;
  int appSettingsOpened = 0;

  @override
  Future<LocationResult> current() async => result;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    if (allow) result = afterPermission;
    return allow;
  }

  @override
  Future<void> openLocationSettings() async => locationSettingsOpened++;

  @override
  Future<void> openAppSettings() async => appSettingsOpened++;
}
