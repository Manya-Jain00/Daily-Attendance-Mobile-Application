import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../location/location_service.dart';
import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/company.dart';
import '../models/day.dart';
import '../models/employee.dart';
import '../models/geo.dart';
import '../models/month.dart';
import '../models/roster.dart';
import 'company_repository.dart';
import 'employee_repository.dart';
import 'firestore_helpers.dart';

/// [EmployeeRepository] backed by Firestore, for [supervisor]'s company
/// ([supervisor] may also be the director).
///
/// [supervisor] is the profile at the time this was opened; open a new one when
/// the supervisor's teams change.
class FirestoreEmployeeRepository implements EmployeeRepository {
  FirestoreEmployeeRepository(
    this.supervisor, {
    FirebaseFirestore? firestore,
    this.location = const DeviceLocationService(),
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final AppUser supervisor;
  final FirebaseFirestore _db;

  @override
  final LocationService location;

  DocumentReference<Map<String, dynamic>> get _company =>
      _db.collection('companies').doc(supervisor.companyId);

  CollectionReference<Map<String, dynamic>> get _employees =>
      _company.collection('employees');

  CollectionReference<Map<String, dynamic>> get _rosters =>
      _company.collection('rosters');

  CollectionReference<Map<String, dynamic>> get _attendance =>
      _company.collection('attendance');

  @override
  List<String> get myTeamIds => supervisor.teamIds;

  @override
  bool get isDirector => supervisor.role == UserRole.director;

  @override
  bool get isAccountant => supervisor.role == UserRole.accountant;

  @override
  Stream<List<Team>> watchTeams() => friendlyErrors(
    _company
        .collection('teams')
        .snapshots()
        .map(
          (q) =>
              q.docs.map((d) => Team.fromMap(d.id, d.data())).toList()
                ..sort((a, b) => compareByName(a.name, b.name)),
        ),
  );

  @override
  Stream<List<Employee>> watchEmployees() => friendlyErrors(
    _employees.snapshots().map(
      (q) =>
          q.docs
              .map((d) => Employee.fromMap(d.id, plainData(d.data())))
              .nonNulls
              .toList()
            ..sort(Employee.compareByEmpId),
    ),
  );

  /// A range on one field only, so no extra index is needed.
  @override
  Stream<List<Roster>> watchRosters(Month month) => friendlyErrors(
    _rosters
        .where('month', isGreaterThanOrEqualTo: month.minus(12).key)
        .where('month', isLessThanOrEqualTo: month.key)
        .snapshots()
        .map(
          (q) => q.docs.map((d) => Roster.fromMap(d.data())).nonNulls.toList(),
        ),
  );

  /// Checks the Emp ID is free, then adds the employee and puts them on the
  /// list in one transaction, so two supervisors can't take the same ID at
  /// once.
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
    final ref = _employees.doc(id);
    try {
      await _db.runTransaction((tx) async {
        final existing = await tx.get(ref);
        if (existing.exists) {
          final other = existing.data()?['name'];
          throw DataFailure(
            'Emp ID $id is already used by '
            '${other is String ? other : 'someone else'}. Choose another, or '
            'use "From another team" to put them on your list.',
          );
        }
        tx
          ..set(ref, {
            'empId': id,
            'name': name.trim(),
            'designation': designation.trim(),
            'active': true,
            'createdAt': FieldValue.serverTimestamp(),
          })
          ..set(
            _rosters.doc(Roster.docId(teamId, month)),
            _rosterData(teamId, month, [...listEmpIds, id]),
          );
      });
    } on DataFailure {
      rethrow;
    } on FirebaseException catch (e) {
      throw DataFailure(firestoreMessage(e));
    }
  }

  @override
  Future<void> updateEmployee(
    String empId, {
    required String name,
    required String designation,
    required bool active,
  }) => guardFirestore(
    () => _employees.doc(empId).update({
      'name': name.trim(),
      'designation': designation.trim(),
      'active': active,
    }),
  );

  @override
  Future<void> setEmployeePhoto(String empId, Uint8List? photo) =>
      guardFirestore(
        () => _employees.doc(empId).update({'photo': photoValue(photo)}),
      );

  @override
  Future<void> saveRoster(String teamId, Month month, List<String> empIds) =>
      guardFirestore(
        () => _rosters
            .doc(Roster.docId(teamId, month))
            .set(_rosterData(teamId, month, empIds)),
      );

  @override
  Stream<CompanySettings> watchSettings() => friendlyErrors(
    _company.snapshots().map(
      (s) => CompanySettings.fromMap(s.data()?['settings']),
    ),
  );

  /// A range on one field only, so no extra index is needed.
  @override
  Stream<List<AttendanceSheet>> watchAttendance(Day from, Day to) =>
      friendlyErrors(
        _attendance
            .where('date', isGreaterThanOrEqualTo: from.key)
            .where('date', isLessThanOrEqualTo: to.key)
            .snapshots()
            .map(
              (q) => q.docs
                  .map((d) => AttendanceSheet.fromMap(plainData(d.data())))
                  .nonNulls
                  .toList(),
            ),
      );

  @override
  Future<void> saveAttendance(
    String teamId,
    Day date,
    Map<String, AttendanceEntry> entries, {
    EntryLocation? location,
  }) => guardFirestore(
    () => _attendance.doc(AttendanceSheet.docId(teamId, date)).set({
      'teamId': teamId,
      'date': date.key,
      'entries': {
        for (final e in entries.entries)
          e.key: {...e.value.toMap(), ..._stampData(e.value.stamp, location)},
      },
      'markedBy': supervisor.phone,
      'updatedAt': FieldValue.serverTimestamp(),
    }),
  );

  /// A kept stamp as it was, or a new one for a new or changed entry.
  Map<String, Object> _stampData(EntryStamp? kept, EntryLocation? location) {
    if (kept != null) {
      return {
        'markedBy': kept.byPhone,
        if (kept.byName.isNotEmpty) 'markedByName': kept.byName,
        'markedAt': kept.at == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(kept.at!),
        if (kept.location case final l?) 'location': l.toMap(),
      };
    }
    return {
      'markedBy': supervisor.phone,
      if (supervisor.name.isNotEmpty) 'markedByName': supervisor.name,
      'markedAt': FieldValue.serverTimestamp(),
      if (location != null) 'location': location.toMap(),
    };
  }

  Map<String, Object> _rosterData(
    String teamId,
    Month month,
    List<String> empIds,
  ) => {
    'teamId': teamId,
    'month': month.key,
    'empIds': empIds.toSet().toList(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
