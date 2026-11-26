import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/phone_number.dart';
import '../../shared/widgets/brand_header.dart';
import '../../shared/widgets/error_banner.dart';
import 'auth_scope.dart';
import 'auth_service.dart';
import 'form_validators.dart';

/// Shown after logging in with a number that isn't in any company yet.
///
/// A director creates their company here and becomes its director. A supervisor
/// whose director hasn't added this number yet is told to ask for it; once
/// the director adds them, the app opens their home by itself.
class CompanySetupScreen extends StatefulWidget {
  const CompanySetupScreen({super.key});

  @override
  State<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends State<CompanySetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _companyController = TextEditingController();
  final _nameController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _companyController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // On success the router opens the director home by itself.
      await AuthScope.of(context).createCompany(
        name: _nameController.text,
        companyName: _companyController.text,
      );
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = AuthScope.of(context);
    final session = auth.session;
    final phone = session is NeedsCompany ? session.phone : '';
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final busy = _busy || session is SessionLoading;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            const BrandHeader(compact: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          margin: EdgeInsets.zero,
                          child: ListTile(
                            leading: const Icon(Icons.badge_outlined),
                            title: const Text('Are you a supervisor?'),
                            subtitle: Text(
                              'Ask your director to add '
                              '${PhoneNumber.format(phone)} in the app. '
                              'This screen will then open your teams.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          'Set up a new company',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'For the director or owner. You can add teams and '
                          'supervisors after this.',
                          style: muted,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _companyController,
                          enabled: !busy,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.organizationName],
                          validator: validateName('Enter the company name'),
                          decoration: const InputDecoration(
                            labelText: 'Company name',
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nameController,
                          enabled: !busy,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.name],
                          validator: validateName('Enter your name'),
                          onFieldSubmitted: (_) => _onSubmit(),
                          decoration: const InputDecoration(
                            labelText: 'Your name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_error != null) ...[
                          ErrorBanner(message: _error!),
                          const SizedBox(height: 16),
                        ],
                        FilledButton(
                          onPressed: busy ? null : _onSubmit,
                          child: busy
                              ? const SizedBox.square(
                                  dimension: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text('Create company'),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: busy ? null : auth.signOut,
                          child: const Text('Log out'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
