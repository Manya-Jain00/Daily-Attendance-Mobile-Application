import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../core/models/app_user.dart';
import '../../core/phone_number.dart';
import '../../shared/widgets/brand_app_bar.dart';
import '../../shared/widgets/load_state.dart';
import '../../shared/widgets/person_avatar.dart';
import '../auth/auth_scope.dart';
import '../auth/auth_service.dart';
import '../../shared/widgets/role_names_scope.dart';
import '../../core/models/role_names.dart';

/// Director, supervisor or accountant: their own name, the mobile number
/// they log in with, and their photo, which they can change here.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _saving = false;

  Future<void> _setPhoto(Uint8List? photo) async {
    setState(() => _saving = true);
    try {
      await AuthScope.of(context).setMyPhoto(photo);
      if (mounted) {
        showMessage(context, photo == null ? 'Photo removed' : 'Photo saved');
      }
    } on AuthFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AuthScope.of(context).session;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: const BrandAppBar(title: 'My profile'),
      body: session is! SignedIn
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                PhotoField(
                  name: session.user.name,
                  photo: session.user.photo,
                  onChanged: _saving ? null : _setPhoto,
                ),
                if (_saving)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(session.user.name),
                        subtitle: const Text('Full name'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.phone_outlined),
                        title: Text(PhoneNumber.format(session.user.phone)),
                        subtitle: const Text(
                          'Mobile number registered with the app',
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.badge_outlined),
                        title: Text(
                          roleLabel(session.user.role, namesOf(context)),
                        ),
                        subtitle: const Text('Role'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  session.user.role == UserRole.director
                      ? 'Your name and number are set when the company is '
                            'created.'
                      : 'To change your name or number, ask your '
                            '${namesOf(context).director.word}.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

String roleLabel(UserRole role, RoleNames names) => switch (role) {
  UserRole.director => names.director.title,
  UserRole.supervisor => names.supervisor.title,
  UserRole.accountant => names.accountant.title,
};
