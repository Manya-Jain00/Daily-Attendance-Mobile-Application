import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/company_repository.dart';
import '../../core/data/employee_repository.dart';
import '../../core/models/employee.dart';
import '../../shared/widgets/brand_app_bar.dart';
import '../../shared/widgets/error_banner.dart';
import '../../shared/widgets/person_avatar.dart';
import '../auth/form_validators.dart';
import 'employees_page.dart';
import '../../shared/widgets/role_names_scope.dart';

/// The director adds a new employee to a team's monthly list (Emp ID, name,
/// designation), or edits one (name, designation, active). The Emp ID can't
/// be changed later.
///
/// A supervisor only views an employee's details here, and can take them off
/// their team's list.
class EmployeeFormPage extends StatefulWidget {
  const EmployeeFormPage({
    super.key,
    required this.repository,
    required this.list,
    required this.allEmployees,
    this.employee,
  });

  final EmployeeRepository repository;

  /// The team and month on screen. A new employee goes on this list.
  final TeamList list;

  /// Everyone in the company, to catch a taken Emp ID before asking the
  /// server (which checks again).
  final List<Employee> allEmployees;

  /// The employee being edited, or null when adding one.
  final Employee? employee;

  @override
  State<EmployeeFormPage> createState() => _EmployeeFormPageState();
}

class _EmployeeFormPageState extends State<EmployeeFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _empIdController = TextEditingController();
  late final _nameController = TextEditingController(
    text: widget.employee?.name,
  );
  late final _designationController = TextEditingController(
    text: widget.employee?.designation,
  );
  late bool _active = widget.employee?.active ?? true;
  late Uint8List? _photo = widget.employee?.photo;

  bool _busy = false;
  String? _error;

  bool get _adding => widget.employee == null;

  /// Only the director adds employees or changes their details.
  bool get _canEdit => widget.repository.isDirector;

  @override
  void dispose() {
    _empIdController.dispose();
    _nameController.dispose();
    _designationController.dispose();
    super.dispose();
  }

  String? _validateEmpId(String? value) {
    final id = Employee.normalizeEmpId(value ?? '');
    if (id.isEmpty) return 'Enter the Emp ID';
    if (!Employee.isValidEmpId(id)) {
      return 'Use up to ${Employee.maxEmpIdLength} letters, numbers or '
          'dashes, e.g. EMP-014';
    }
    for (final e in widget.allEmployees) {
      if (e.empId == id) {
        return 'Already used by ${e.name}. To put them on this list, use '
            '"From another team"';
      }
    }
    return null;
  }

  String? _validateDesignation(String? value) =>
      (value ?? '').trim().length > 100 ? 'Keep it under 100 characters' : null;

  Future<void> _save() async {
    if (_busy || !_canEdit || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final employee = widget.employee;
    final name = _nameController.text.trim();
    final designation = _designationController.text.trim();

    final photo = _photo;
    final photoChanged = !listEquals(photo, employee?.photo);
    if (employee != null) {
      final detailsChanged =
          name != employee.name ||
          designation != employee.designation ||
          _active != employee.active;
      if (!detailsChanged && !photoChanged) {
        Navigator.pop(context);
        return;
      }
      if (employee.active && !_active && !await _confirmDeactivate()) return;
    }

    await _run(() async {
      final repo = widget.repository;
      if (employee == null) {
        final empId = Employee.normalizeEmpId(_empIdController.text);
        await repo.addEmployee(
          empId: empId,
          name: name,
          designation: designation,
          teamId: widget.list.team.id,
          month: widget.list.month,
          listEmpIds: widget.list.empIds,
        );
        if (photo != null) await repo.setEmployeePhoto(empId, photo);
      } else {
        if (name != employee.name ||
            designation != employee.designation ||
            _active != employee.active) {
          await repo.updateEmployee(
            employee.empId,
            name: name,
            designation: designation,
            active: _active,
          );
        }
        if (photoChanged) await repo.setEmployeePhoto(employee.empId, photo);
      }
    }, employee == null ? '$name added' : 'Saved');
  }

  Future<void> _removeFromList() async {
    final employee = widget.employee!;
    final list = widget.list;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Take ${employee.name} off ${list.team.name}?'),
        content: Text(
          "They won't be on ${list.team.name}'s attendance sheet from "
          '${list.month.label} on. Their past attendance is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Take off'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _run(
      () => widget.repository.saveRoster(list.team.id, list.month, [
        for (final id in list.empIds)
          if (id != employee.empId) id,
      ]),
      '${employee.name} taken off ${list.team.name}',
    );
  }

  /// Runs a save, then closes the page with [done], or shows the error.
  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      Navigator.pop(context);
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
        title: Text('Deactivate ${widget.employee!.name}?'),
        content: const Text(
          "Use this for someone who has left the company. They won't appear "
          'on any attendance sheet. Their past attendance is kept, and you '
          'can turn them back on at any time.',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final employee = widget.employee;
    final list = widget.list;
    final canRemove =
        employee != null && list.editable && list.contains(employee.empId);
    final canEdit = _canEdit;
    return Scaffold(
      appBar: BrandAppBar(
        title: _adding
            ? 'Add ${namesOf(context).employee.word}'
            : canEdit
            ? 'Edit ${namesOf(context).employee.word}'
            : namesOf(context).employee.title,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (canEdit || _photo != null) ...[
              PhotoField(
                name: _nameController.text,
                photo: _photo,
                onChanged: canEdit && !_busy
                    ? (photo) => setState(() => _photo = photo)
                    : null,
                hint:
                    'A photo helps ${namesOf(context).supervisor.words} who cannot read names.',
              ),
              const SizedBox(height: 16),
            ],
            if (employee == null) ...[
              Text(
                "Goes on ${list.team.name}'s list from ${list.month.label}.",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _empIdController,
                enabled: !_busy,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                maxLength: Employee.maxEmpIdLength,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),
                ],
                validator: _validateEmpId,
                decoration: const InputDecoration(
                  labelText: 'Emp ID',
                  helperText: "e.g. EMP-014. Can't be changed later",
                  prefixIcon: Icon(Icons.tag),
                ),
              ),
            ] else
              Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: const Icon(Icons.tag),
                  title: Text(employee.empId),
                  subtitle: const Text('Emp ID'),
                ),
              ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              enabled: !_busy,
              readOnly: !canEdit,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: validateName(
                "Enter the ${namesOf(context).employee.word}'s name",
              ),
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _designationController,
              enabled: !_busy,
              readOnly: !canEdit,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              validator: _validateDesignation,
              onFieldSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: canEdit ? 'Designation (optional)' : 'Designation',
                hintText: canEdit ? 'e.g. Accountant' : null,
                prefixIcon: Icon(Icons.work_outline),
              ),
            ),
            if (employee != null && canEdit) ...[
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile(
                  title: const Text('Active'),
                  subtitle: const Text(
                    'Turn off for someone who has left the company. Their '
                    'past attendance is kept.',
                  ),
                  value: _active,
                  onChanged: _busy ? null : (v) => setState(() => _active = v),
                ),
              ),
            ],
            if (employee != null && !canEdit) ...[
              const SizedBox(height: 16),
              Text(
                [
                  if (!employee.active) 'Inactive: has left the company.',
                  'Only the ${namesOf(context).director.word} can change these details or '
                      'deactivate ${namesOf(context).employee.aWord}.',
                ].join(' '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: 16),
            ],
            if (canEdit)
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: theme.colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        _adding
                            ? 'Add ${namesOf(context).employee.word}'
                            : 'Save changes',
                      ),
              ),
            if (canRemove) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _removeFromList,
                icon: const Icon(Icons.person_remove_outlined),
                label: Text('Take off ${list.team.name} list'),
              ),
              const SizedBox(height: 4),
              Text(
                'For someone who moved to another team. From '
                '${list.month.label} on.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
