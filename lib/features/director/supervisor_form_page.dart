import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/company_repository.dart';
import '../../core/models/app_user.dart';
import '../../core/models/company.dart';
import '../../core/phone_number.dart';
import '../../shared/widgets/brand_app_bar.dart';
import '../../shared/widgets/error_banner.dart';
import '../../shared/widgets/person_avatar.dart';
import '../auth/form_validators.dart';
import '../../shared/widgets/role_names_scope.dart';
import '../../core/models/role_names.dart';

/// Director: add a supervisor (name, mobile number, teams), or edit one (name,
/// teams, active). The number is their login, so it can't be changed here.
///
/// With [role] [UserRole.accountant] it adds or edits an accountant the same
/// way, without teams: an accountant sees every team, view only.
class SupervisorFormPage extends StatefulWidget {
  const SupervisorFormPage({
    super.key,
    required this.repository,
    required this.teams,
    required this.people,
    this.supervisor,
    this.role = UserRole.supervisor,
  });

  final CompanyRepository repository;
  final List<Team> teams;

  /// Everyone already added (supervisors and accountants), to catch a number
  /// that's already in the company before asking the server.
  final List<AppUser> people;

  /// The person being edited, or null when adding one.
  final AppUser? supervisor;

  /// [UserRole.supervisor] or [UserRole.accountant].
  final UserRole role;

  @override
  State<SupervisorFormPage> createState() => _SupervisorFormPageState();
}

class _SupervisorFormPageState extends State<SupervisorFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.supervisor?.name,
  );
  final _phoneController = TextEditingController();

  /// Kept in the order of [SupervisorFormPage.teams], plus any ids the supervisor
  /// has that this list doesn't know about, so saving never drops them.
  late final Set<String> _teamIds = {...?widget.supervisor?.teamIds};
  late bool _active = widget.supervisor?.active ?? true;
  late Uint8List? _photo = widget.supervisor?.photo;

  bool _busy = false;
  String? _error;

  bool get _adding => widget.supervisor == null;

  bool get _isAccountant => widget.role == UserRole.accountant;

  /// "supervisor" or "accountant", for the screen's wording.
  RoleName get _role =>
      _isAccountant ? namesOf(context).accountant : namesOf(context).supervisor;
  String get _roleName => _role.word;
  String get _roleTitle => _role.title;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _validatePhone(String? value) {
    final problem = validatePhone(value);
    if (problem != null) return problem;
    final phone = PhoneNumber.normalize(value!);
    final taken = widget.people.where((m) => m.phone == phone).firstOrNull;
    if (taken == null) return null;
    return taken.role == UserRole.accountant
        ? '${_cap(namesOf(context).accountant.aWord)} with this number is already added'
        : '${_cap(namesOf(context).supervisor.aWord)} with this number is already added';
  }

  List<String> get _orderedTeamIds => [
    for (final team in widget.teams)
      if (_teamIds.contains(team.id)) team.id,
    ..._teamIds.where((id) => !widget.teams.any((t) => t.id == id)),
  ];

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final supervisor = widget.supervisor;

    final photoChanged = !listEquals(_photo, supervisor?.photo);
    final detailsChanged =
        supervisor == null ||
        _nameController.text.trim() != supervisor.name ||
        _active != supervisor.active ||
        _teamIds.length != supervisor.teamIds.length ||
        !_teamIds.containsAll(supervisor.teamIds);
    if (supervisor != null) {
      if (!detailsChanged && !photoChanged) {
        Navigator.pop(context);
        return;
      }
      if (supervisor.active && !_active && !await _confirmDeactivate()) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (supervisor == null) {
        final phone = PhoneNumber.normalize(_phoneController.text)!;
        if (_isAccountant) {
          await widget.repository.addAccountant(
            name: _nameController.text,
            phone: phone,
          );
        } else {
          await widget.repository.addSupervisor(
            name: _nameController.text,
            phone: phone,
            teamIds: _orderedTeamIds,
          );
        }
        if (_photo case final photo?) {
          await widget.repository.setPersonPhoto(phone, photo);
        }
        if (!mounted) return;
        setState(() => _busy = false);
        await _showLoginDetails();
      } else if (!detailsChanged) {
        // Only the photo changed.
      } else if (_isAccountant) {
        await widget.repository.updateAccountant(
          supervisor.phone,
          name: _nameController.text,
          active: _active,
        );
      } else {
        await widget.repository.updateSupervisor(
          supervisor.phone,
          name: _nameController.text,
          teamIds: _orderedTeamIds,
          active: _active,
        );
      }
      if (supervisor != null && photoChanged) {
        await widget.repository.setPersonPhoto(supervisor.phone, _photo);
      }
      if (mounted) Navigator.pop(context);
    } on DataFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDeactivate() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Deactivate ${widget.supervisor!.name}?'),
        content: const Text(
          "They will be logged out and can't use the app until you turn "
          'them back on. Their past attendance entries are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    return sure == true;
  }

  /// Tells the director what to pass on: there's no password, just the
  /// number.
  Future<void> _showLoginDetails() {
    final name = _nameController.text.trim();
    final phone = PhoneNumber.format(
      PhoneNumber.normalize(_phoneController.text)!,
    );
    final message =
        'You can now use the Daily Attendance app. Log in with your mobile '
        'number $phone and the code that comes by SMS.';
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('$_roleTitle added'),
        content: Text(
          '$name can now log in with $phone. The app sends them a code by '
          'SMS each time they log in on a new phone.',
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: message));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Message copied')));
              }
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy message'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supervisor = widget.supervisor;
    return Scaffold(
      appBar: BrandAppBar(
        title: _adding ? 'Add $_roleName' : 'Edit $_roleName',
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            PhotoField(
              name: _nameController.text,
              photo: _photo,
              onChanged: _busy ? null : (p) => setState(() => _photo = p),
              hint: 'Shown on their profile. They can also add it themselves.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: validateName("Enter the $_roleName's name"),
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            if (supervisor == null)
              TextFormField(
                controller: _phoneController,
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
                  LengthLimitingTextInputFormatter(16),
                ],
                validator: _validatePhone,
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  helperText: 'They log in with this number',
                  prefixText: '${PhoneNumber.defaultCountryCode} ',
                  prefixIcon: Icon(Icons.phone_android_outlined),
                ),
              )
            else
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.phone_android_outlined),
                  title: Text(PhoneNumber.format(supervisor.phone)),
                  subtitle: const Text('Mobile number · their login'),
                ),
              ),
            if (_isAccountant) ...[
              const SizedBox(height: 16),
              Text(
                '${_cap(namesOf(context).accountant.aWord)} sees every team, the dashboard, '
                '${namesOf(context).employee.word} '
                "history and the reports (with the Excel file), but can't "
                'change anything.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              const SizedBox(height: 24),
              Text('Teams', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                widget.teams.isEmpty
                    ? 'No teams yet. Add them in the Teams tab, then come back '
                          'to assign them.'
                    : 'The teams this ${namesOf(context).supervisor.word} marks attendance for.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final team in widget.teams)
                    FilterChip(
                      label: Text(team.name),
                      selected: _teamIds.contains(team.id),
                      onSelected: _busy
                          ? null
                          : (on) => setState(
                              () => on
                                  ? _teamIds.add(team.id)
                                  : _teamIds.remove(team.id),
                            ),
                    ),
                ],
              ),
            ],
            if (supervisor != null) ...[
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile(
                  title: const Text('Active'),
                  subtitle: Text(
                    "Inactive ${_roleName}s can't log in to the app.",
                  ),
                  value: _active,
                  onChanged: _busy ? null : (v) => setState(() => _active = v),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: 16),
            ],
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(_adding ? 'Add $_roleName' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "a supervisor" -> "A supervisor".
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
