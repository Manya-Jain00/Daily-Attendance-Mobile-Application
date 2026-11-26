import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/company_repository.dart';
import '../../core/models/app_user.dart';
import '../../core/models/company.dart';
import '../../core/phone_number.dart';
import '../../shared/widgets/brand_app_bar.dart';
import '../../shared/widgets/error_banner.dart';
import '../auth/form_validators.dart';

/// Director: add a manager (name, mobile number, teams), or edit one (name,
/// teams, active). The number is their login, so it can't be changed here.
class ManagerFormPage extends StatefulWidget {
  const ManagerFormPage({
    super.key,
    required this.repository,
    required this.teams,
    required this.managers,
    this.manager,
  });

  final CompanyRepository repository;
  final List<Team> teams;

  /// Everyone already added, to catch a number that's already in the
  /// company before asking the server.
  final List<AppUser> managers;

  /// The manager being edited, or null when adding one.
  final AppUser? manager;

  @override
  State<ManagerFormPage> createState() => _ManagerFormPageState();
}

class _ManagerFormPageState extends State<ManagerFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.manager?.name,
  );
  final _phoneController = TextEditingController();

  /// Kept in the order of [ManagerFormPage.teams], plus any ids the manager
  /// has that this list doesn't know about, so saving never drops them.
  late final Set<String> _teamIds = {...?widget.manager?.teamIds};
  late bool _active = widget.manager?.active ?? true;

  bool _busy = false;
  String? _error;

  bool get _adding => widget.manager == null;

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
    final taken = widget.managers.any((m) => m.phone == phone);
    return taken ? 'A manager with this number is already added' : null;
  }

  List<String> get _orderedTeamIds => [
    for (final team in widget.teams)
      if (_teamIds.contains(team.id)) team.id,
    ..._teamIds.where((id) => !widget.teams.any((t) => t.id == id)),
  ];

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final manager = widget.manager;

    if (manager != null) {
      final unchanged =
          _nameController.text.trim() == manager.name &&
          _active == manager.active &&
          _teamIds.length == manager.teamIds.length &&
          _teamIds.containsAll(manager.teamIds);
      if (unchanged) {
        Navigator.pop(context);
        return;
      }
      if (manager.active && !_active && !await _confirmDeactivate()) return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (manager == null) {
        await widget.repository.addManager(
          name: _nameController.text,
          phone: PhoneNumber.normalize(_phoneController.text)!,
          teamIds: _orderedTeamIds,
        );
        if (!mounted) return;
        setState(() => _busy = false);
        await _showLoginDetails();
      } else {
        await widget.repository.updateManager(
          manager.phone,
          name: _nameController.text,
          teamIds: _orderedTeamIds,
          active: _active,
        );
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
        title: Text('Deactivate ${widget.manager!.name}?'),
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
        title: const Text('Manager added'),
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
    final manager = widget.manager;
    return Scaffold(
      appBar: BrandAppBar(title: _adding ? 'Add manager' : 'Edit manager'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _nameController,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: validateName("Enter the manager's name"),
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            if (manager == null)
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
                  title: Text(PhoneNumber.format(manager.phone)),
                  subtitle: const Text('Mobile number · their login'),
                ),
              ),
            const SizedBox(height: 24),
            Text('Teams', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              widget.teams.isEmpty
                  ? 'No teams yet. Add them in the Teams tab, then come back '
                        'to assign them.'
                  : 'The teams this manager marks attendance for.',
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
            if (manager != null) ...[
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile(
                  title: const Text('Active'),
                  subtitle: const Text(
                    "Inactive managers can't log in to the app.",
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
                  : Text(_adding ? 'Add manager' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
