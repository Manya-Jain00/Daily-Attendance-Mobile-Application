import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/data/firestore_company_repository.dart';
import 'core/data/firestore_employee_repository.dart';
import 'features/auth/firebase_auth_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(
    DailyAttendanceApp(
      auth: FirebaseAuthService(),
      openCompany: FirestoreCompanyRepository.new,
      openEmployees: FirestoreEmployeeRepository.new,
    ),
  );
}
