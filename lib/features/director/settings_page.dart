import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../core/data/company_repository.dart';
import '../../core/location/location_service.dart';
import '../../core/models/company.dart';
import '../../core/models/geo.dart';
import '../../core/models/role_names.dart';
import '../../shared/widgets/load_state.dart';
import '../../shared/widgets/location_prompt.dart';
import '../auth/form_validators.dart';
import '../../shared/widgets/role_names_scope.dart';

/// Director: the company name and office rules (office hours, late time, half-day
/// rule, supervisor edit window).
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repository,
    required this.location,
  });

  final CompanyRepository repository;

  /// To set the office location to where the director is.
  final LocationService location;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  /// The company's own names for its roles; blank means the default.
  final _roleControllers = {
    for (final key in RoleNames.keys) key: TextEditingController(),
  };
  late final StreamSubscription<Company> _sub;

  /// What's saved on the server, and the director's unsaved edits to it.
  Company? _saved;
  CompanySettings? _draft;
  Object? _loadError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
    _sub = widget.repository.watchCompany().listen(
      (company) => setState(() {
        final hadEdits = _dirty;
        _saved = company;
        _loadError = null;
        // Don't throw away the director's edits when the saved copy changes.
        if (!hadEdits) {
          _draft = company.settings;
          _nameController.text = company.name;
          _showRoleNames(company.settings.roleNames);
        }
      }),
      onError: (Object e) => setState(() => _loadError = e),
    );
  }

  @override
  void dispose() {
    _sub.cancel();
    _nameController.dispose();
    for (final c in _roleControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _dirty {
    final saved = _saved;
    if (saved == null) return false;
    return _draft != saved.settings ||
        _nameController.text.trim() != saved.name;
  }

  void _edit(CompanySettings Function(CompanySettings) change) =>
      setState(() => _draft = change(_draft!));

  Future<void> _pickTime(
    String current,
    String helpText,
    CompanySettings Function(CompanySettings, String) apply,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parseTime(current),
      helpText: helpText,
    );
    if (picked != null) _edit((s) => apply(s, _timeText(picked)));
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await widget.repository.updateCompany(
        name: _nameController.text,
        settings: _draft!,
      );
      if (mounted) showMessage(context, 'Settings saved');
    } on DataFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sets the office to where the director's phone is now.
  Future<void> _useMyLocation() async {
    setState(() => _busy = true);
    try {
      final here = await askLocation(
        context,
        widget.location,
        why:
            'The office location is set to where your phone is now, so '
            'stand in the office.',
      );
      if (here == null || !mounted) return;
      _edit((s) => s.withOffice(here.point));
      showMessage(
        context,
        'Office set to where you are (accurate to about '
        '${displayDistance(here.accuracy)}). Tap Save changes to keep it.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fills the name fields: renamed roles as typed, defaults left blank.
  void _showRoleNames(RoleNames names) {
    for (final key in RoleNames.keys) {
      final role = names.byKey(key);
      _roleControllers[key]!.text = role.isDefault ? '' : role.title;
    }
  }

  void _discard() => setState(() {
    _draft = _saved!.settings;
    _nameController.text = _saved!.name;
    _showRoleNames(_saved!.settings.roleNames);
  });

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load',
        message: '$_loadError',
      );
    }
    final draft = _draft;
    if (draft == null) return const Center(child: CircularProgressIndicator());

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('Company'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextFormField(
                controller: _nameController,
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                validator: validateName('Enter the company name'),
                decoration: const InputDecoration(
                  labelText: 'Company name',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
            ),
          ),
          const _SectionTitle('Office hours'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                _TimeTile(
                  icon: Icons.login,
                  title: 'Office starts',
                  value: draft.officeStart,
                  onTap: _busy
                      ? null
                      : () => _pickTime(
                          draft.officeStart,
                          'Office starts at',
                          (s, t) => s.copyWith(officeStart: t),
                        ),
                ),
                const Divider(height: 1),
                _TimeTile(
                  icon: Icons.logout,
                  title: 'Office ends',
                  value: draft.officeEnd,
                  onTap: _busy
                      ? null
                      : () => _pickTime(
                          draft.officeEnd,
                          'Office ends at',
                          (s, t) => s.copyWith(officeEnd: t),
                        ),
                ),
                const Divider(height: 1),
                _TimeTile(
                  icon: Icons.schedule,
                  title: 'Late after',
                  subtitle: 'Arriving after this is marked late',
                  value: draft.lateAfter,
                  onTap: _busy
                      ? null
                      : () => _pickTime(
                          draft.lateAfter,
                          'Late after',
                          (s, t) => s.copyWith(lateAfter: t),
                        ),
                ),
              ],
            ),
          ),
          const _SectionTitle('Rules'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                _StepperTile(
                  icon: Icons.timelapse,
                  title: 'Half day',
                  subtitle: 'Counted when someone works less than this',
                  value: '${_hoursText(draft.halfDayBelowHours)} h',
                  semanticsLabel: 'half-day hours',
                  onMinus: _busy || draft.halfDayBelowHours <= 0.5
                      ? null
                      : () => _edit(
                          (s) => s.copyWith(
                            halfDayBelowHours: s.halfDayBelowHours - 0.5,
                          ),
                        ),
                  onPlus:
                      _busy ||
                          draft.halfDayBelowHours >=
                              CompanySettings.maxHalfDayHours
                      ? null
                      : () => _edit(
                          (s) => s.copyWith(
                            halfDayBelowHours: s.halfDayBelowHours + 0.5,
                          ),
                        ),
                ),
                const Divider(height: 1),
                _StepperTile(
                  icon: Icons.edit_calendar_outlined,
                  title: '${namesOf(context).supervisor.title} edit window',
                  subtitle:
                      '${namesOf(context).supervisor.titles} can correct this many past days',
                  value: '${draft.supervisorEditDays} d',
                  semanticsLabel: 'edit window days',
                  onMinus: _busy || draft.supervisorEditDays <= 0
                      ? null
                      : () => _edit(
                          (s) => s.copyWith(
                            supervisorEditDays: s.supervisorEditDays - 1,
                          ),
                        ),
                  onPlus:
                      _busy ||
                          draft.supervisorEditDays >=
                              CompanySettings.maxSupervisorEditDays
                      ? null
                      : () => _edit(
                          (s) => s.copyWith(
                            supervisorEditDays: s.supervisorEditDays + 1,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const _SectionTitle('Names in the app'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'What your company calls each role, on every screen and '
                    'in the Excel file. Leave blank for the usual name.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  for (final key in RoleNames.keys) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _roleControllers[key],
                      enabled: !_busy,
                      maxLength: RoleName.maxLength,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (v) => _edit(
                        (s) =>
                            s.copyWith(roleNames: s.roleNames.rename(key, v)),
                      ),
                      decoration: InputDecoration(
                        labelText: RoleNames.defaultFor(key),
                        hintText: _roleExamples[key],
                        counterText: '',
                        prefixIcon: Icon(_roleIcons[key]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const _SectionTitle('Office location'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(draft.office == null ? 'Not set' : 'Office set'),
                  subtitle: Text(
                    draft.office == null
                        ? 'Set it while you are in the office. Attendance '
                              'saved far from it is then flagged.'
                        : 'Attendance saved more than '
                              '${displayDistance(draft.officeRadiusM.toDouble())} '
                              'away is flagged in red.',
                  ),
                  trailing: draft.office == null
                      ? null
                      : TextButton(
                          onPressed: () => openMap(context, draft.office!),
                          child: const Text('Map'),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _useMyLocation,
                        icon: const Icon(Icons.my_location),
                        label: Text(
                          draft.office == null
                              ? 'Use where I am now'
                              : 'Move to where I am now',
                        ),
                      ),
                      if (draft.office != null)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit((s) => s.withOffice(null)),
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                _StepperTile(
                  icon: Icons.social_distance_outlined,
                  title: 'Flag entries further than',
                  subtitle: 'GPS indoors can be off by 20-100 m',
                  value: displayDistance(draft.officeRadiusM.toDouble()),
                  semanticsLabel: 'office distance',
                  onMinus:
                      _busy ||
                          draft.officeRadiusM <=
                              CompanySettings.minOfficeRadiusM
                      ? null
                      : () => _edit(
                          (s) =>
                              s.copyWith(officeRadiusM: s.officeRadiusM - 100),
                        ),
                  onPlus:
                      _busy ||
                          draft.officeRadiusM >=
                              CompanySettings.maxOfficeRadiusM
                      ? null
                      : () => _edit(
                          (s) =>
                              s.copyWith(officeRadiusM: s.officeRadiusM + 100),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy || !_dirty ? null : _save,
            child: _busy
                ? const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Save changes'),
          ),
          if (_dirty && !_busy) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: _discard, child: const Text('Undo changes')),
          ],
        ],
      ),
    );
  }
}

TimeOfDay _parseTime(String text) {
  final [hour, minute] = text.split(':').map(int.parse).toList();
  return TimeOfDay(hour: hour, minute: minute);
}

String _timeText(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

String _hoursText(num hours) =>
    hours == hours.roundToDouble() ? '${hours.round()}' : '$hours';

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Text(
        _parseTime(value).format(context),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: onTap,
    );
  }
}

class _StepperTile extends StatelessWidget {
  const _StepperTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.semanticsLabel,
    required this.onMinus,
    required this.onPlus,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final String semanticsLabel;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyLarge),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Less $semanticsLabel',
            onPressed: onMinus,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 44,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'More $semanticsLabel',
            onPressed: onPlus,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}

const _roleExamples = {
  'director': 'e.g. Owner',
  'supervisor': 'e.g. Foreman',
  'accountant': 'e.g. Munim',
  'employee': 'e.g. Worker',
};

const _roleIcons = {
  'director': Icons.workspace_premium_outlined,
  'supervisor': Icons.badge_outlined,
  'accountant': Icons.calculate_outlined,
  'employee': Icons.people_outline,
};
