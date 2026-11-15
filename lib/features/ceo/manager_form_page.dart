import 'dart:math';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/company_repository.dart';
import '../../core/manager_login.dart';
import '../../core/models/app_user.dart';
import '../../core/models/company.dart';
import '../../shared/widgets/brand_app_bar.dart';
import '../../shared/widgets/error_banner.dart';
import '../auth/form_validators.dart';

/// CEO: add a manager (name, username, PIN, teams), or edit one (name,
/// teams, active). The username and PIN can't be changed here.
class ManagerFormPage extends StatefulWidget {
  const ManagerFormPage({
    super.key,
    required this.repository,
    required this.companyCode,
    required this.teams,
    required this.managers,
    this.manager,
  });

  final CompanyRepository repository;
  final String companyCode;
  final List<Team> teams;

  /// Everyone already added, to catch a taken username before asking the
  /// server.
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
  final _usernameController = TextEditingController();
  final _pinController = TextEditingController();

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
    _usernameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  String? _validateUsername(String? value) {
    final problem = validateNewUsername(value);
    if (problem != null) return problem;
    final username = ManagerLogin.normalizeUsername(value!);
    final taken = widget.managers.any((m) => m.username == username);
    return taken ? 'This username is already taken' : null;
  }

  void _randomPin() {
    final random = Random.secure();
    _pinController.text = List.generate(
      ManagerLogin.minPinLength,
      (_) => random.nextInt(10),
    ).join();
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
          username: _usernameController.text,
          pin: _pinController.text,
          teamIds: _orderedTeamIds,
        );
        if (!mounted) return;
        setState(() => _busy = false);
        await _showLoginDetails();
      } else {
        await widget.repository.updateManager(
          manager.uid,
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

  /// The PIN isn't stored anywhere readable, so this is the CEO's only
  /// chance to see it.
  Future<void> _showLoginDetails() {
    final name = _nameController.text.trim();
    final details =
        'Daily Attendance login for $name\n'
        'Company code: ${widget.companyCode}\n'
        'Username: ${ManagerLogin.normalizeUsername(_usernameController.text)}\n'
        'PIN: ${_pinController.text}';
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Manager added'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Give these login details to $name. Note the PIN now: it '
                "can't be shown again.",
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  details.split('\n').skip(1).join('\n'),
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: details));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Login details copied')),
                  );
                }
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        );
      },
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
            if (manager == null) ...[
              TextFormField(
                controller: _usernameController,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                validator: _validateUsername,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  helperText: 'They type this to log in, e.g. ravi',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _pinController,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: maxPinLength,
                validator: validateNewPin,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  helperText:
                      '${ManagerLogin.minPinLength} to $maxPinLength digits',
                  prefixIcon: const Icon(Icons.pin_outlined),
                  suffixIcon: IconButton(
                    tooltip: 'Make a random PIN',
                    icon: const Icon(Icons.casino_outlined),
                    onPressed: _busy ? null : _randomPin,
                  ),
                ),
              ),
            ] else
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.alternate_email),
                  title: Text(manager.username),
                  subtitle: Text(
                    'Username · company code ${widget.companyCode}',
                  ),
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
