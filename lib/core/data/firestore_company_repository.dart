import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../manager_login.dart';
import '../models/app_user.dart';
import '../models/company.dart';
import '../models/month.dart';
import '../models/roster.dart';
import 'company_repository.dart';
import 'firestore_helpers.dart';

/// [CompanyRepository] backed by Firestore, for the company of [ceo].
class FirestoreCompanyRepository implements CompanyRepository {
  FirestoreCompanyRepository(this.ceo, {FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final AppUser ceo;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _company =>
      _db.collection('companies').doc(ceo.companyId);

  CollectionReference<Map<String, dynamic>> get _teams =>
      _company.collection('teams');

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  /// Everyone in this company. The security rules only let a CEO list the
  /// profiles of their own company, so the filter is required.
  Query<Map<String, dynamic>> get _companyUsers =>
      _users.where('companyId', isEqualTo: ceo.companyId);

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

  /// Firebase can only create a login by signing in as it. Doing that on the
  /// app's main connection would log the CEO out, so the manager's login is
  /// made on a second, background connection to the same project.
  ///
  /// The profile is then written as the CEO. If that fails, the new login is
  /// removed again so the username can be reused.
  @override
  Future<void> addManager({
    required String name,
    required String username,
    required String pin,
    required List<String> teamIds,
  }) async {
    final cleanUsername = ManagerLogin.normalizeUsername(username);
    final email = ManagerLogin.email(
      companyCode: ceo.companyCode,
      username: cleanUsername,
    );
    final helperAuth = FirebaseAuth.instanceFor(app: await _helperApp());

    final UserCredential credential;
    try {
      credential = await helperAuth.createUserWithEmailAndPassword(
        email: email,
        password: pin,
      );
    } on FirebaseAuthException catch (e) {
      throw DataFailure(switch (e.code) {
        'email-already-in-use' =>
          'The username "$cleanUsername" is already taken in your company. '
              'Choose another.',
        'weak-password' => 'Choose a longer PIN (at least 6 digits).',
        'network-request-failed' =>
          'No internet connection. Check your connection and try again.',
        'too-many-requests' =>
          'Too many attempts. Wait a few minutes and try again.',
        _ => 'Could not create the login (${e.code}). Please try again.',
      });
    }

    final newLogin = credential.user!;
    try {
      await guardFirestore(
        () => _users.doc(newLogin.uid).set({
          'companyId': ceo.companyId,
          'companyCode': ceo.companyCode,
          'role': UserRole.manager.name,
          'name': name.trim(),
          'username': cleanUsername,
          'email': email,
          'teamIds': teamIds,
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
        }),
      );
    } catch (_) {
      try {
        await newLogin.delete();
      } catch (_) {
        // Left behind; the username stays taken until removed in the console.
      }
      rethrow;
    } finally {
      await helperAuth.signOut();
    }
  }

  Future<FirebaseApp> _helperApp() async {
    const name = 'manager-setup';
    for (final app in Firebase.apps) {
      if (app.name == name) return app;
    }
    return Firebase.initializeApp(name: name, options: _db.app.options);
  }

  @override
  Future<void> updateManager(
    String uid, {
    required String name,
    required List<String> teamIds,
    required bool active,
  }) => guardFirestore(
    () => _users.doc(uid).update({
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
