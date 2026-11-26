import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/company.dart';
import '../models/month.dart';
import '../models/roster.dart';
import 'company_repository.dart';
import 'firestore_helpers.dart';

/// [CompanyRepository] backed by Firestore, for the company of [director].
class FirestoreCompanyRepository implements CompanyRepository {
  FirestoreCompanyRepository(this.director, {FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final AppUser director;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _company =>
      _db.collection('companies').doc(director.companyId);

  CollectionReference<Map<String, dynamic>> get _teams =>
      _company.collection('teams');

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  /// Everyone in this company. The security rules only let a director list the
  /// profiles of their own company, so the filter is required.
  Query<Map<String, dynamic>> get _companyUsers =>
      _users.where('companyId', isEqualTo: director.companyId);

  @override
  Stream<Company> watchCompany() => friendlyErrors(
    _company.snapshots().map((s) => Company.fromMap(s.data() ?? const {})),
  );

  @override
  Stream<List<Team>> watchTeams() => friendlyErrors(
    _teams.snapshots().map(
      (q) =>
          q.docs.map((d) => Team.fromMap(d.id, d.data())).toList()
            ..sort((a, b) => compareByName(a.name, b.name)),
    ),
  );

  @override
  Stream<List<AppUser>> watchManagers() => friendlyErrors(
    _companyUsers
        .where('role', isEqualTo: UserRole.manager.name)
        .snapshots()
        .map(
          (q) =>
              q.docs
                  .map((d) => AppUser.fromMap(d.id, d.data()))
                  .nonNulls
                  .toList()
                ..sort((a, b) => compareByName(a.name, b.name)),
        ),
  );

  @override
  Future<void> addTeam(String name) => guardFirestore(
    () => _teams.add({
      'name': name.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    }),
  );

  @override
  Future<void> renameTeam(String teamId, String name) =>
      guardFirestore(() => _teams.doc(teamId).update({'name': name.trim()}));

  @override
  Future<void> deleteTeam(String teamId) => guardFirestore(() async {
    // Refused while the team's list for this month has anyone on it. (Its
    // past lists are kept, for the attendance history.)
    final month = Month.now();
    final lists = await _company
        .collection('rosters')
        .where('teamId', isEqualTo: teamId)
        .get();
    final current = EffectiveRoster.of(
      lists.docs.map((d) => Roster.fromMap(d.data())).nonNulls,
      teamId,
      month,
    );
    if (current.empIds.isNotEmpty) {
      throw DataFailure(
        'This team still has employees on its list for ${month.label}. Its '
        'manager must take them off the list first.',
      );
    }
    // Filtered here rather than in the query so no extra index is needed.
    final people = await _companyUsers.get();
    final batch = _db.batch()..delete(_teams.doc(teamId));
    for (final person in people.docs) {
      final data = person.data();
      final teamIds = data['teamIds'];
      if (data['role'] == UserRole.manager.name &&
          teamIds is List &&
          teamIds.contains(teamId)) {
        batch.update(person.reference, {
          'teamIds': FieldValue.arrayRemove([teamId]),
        });
      }
    }
    await batch.commit();
  });

  /// The profile is keyed by the number, so it's ready before the manager
  /// ever logs in. The rules refuse a number that's already in the app (that
  /// would be an update of someone else's profile).
  @override
  Future<void> addManager({
    required String name,
    required String phone,
    required List<String> teamIds,
  }) async {
    try {
      await _users.doc(phone).set({
        'companyId': director.companyId,
        'role': UserRole.manager.name,
        'name': name.trim(),
        'phone': phone,
        'teamIds': teamIds,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const DataFailure(
          'This number is already used in the app, by someone in your '
          'company or another firm. Check the number.',
        );
      }
      throw DataFailure(firestoreMessage(e));
    }
  }

  @override
  Future<void> updateManager(
    String phone, {
    required String name,
    required List<String> teamIds,
    required bool active,
  }) => guardFirestore(
    () => _users.doc(phone).update({
      'name': name.trim(),
      'teamIds': teamIds,
      'active': active,
    }),
  );

  @override
  Future<void> updateCompany({
    required String name,
    required CompanySettings settings,
  }) => guardFirestore(
    () => _company.update({'name': name.trim(), 'settings': settings.toMap()}),
  );
}
