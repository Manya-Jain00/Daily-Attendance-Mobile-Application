import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../routing/app_router.dart';
import '../../shared/widgets/brand_header.dart';
import '../../shared/widgets/error_banner.dart';
import 'auth_scope.dart';
import 'auth_service.dart';
import 'form_validators.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Managers log in with company code + username + PIN; CEOs with email.
enum _LoginMode { manager, ceo }

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _LoginMode _mode = _LoginMode.manager;
  bool _hidePassword = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onLogin() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // On success the router moves on to the right home screen by itself.
      final auth = AuthScope.of(context);
      if (_mode == _LoginMode.manager) {
        await auth.signInManager(
          companyCode: _codeController.text,
          username: _usernameController.text,
          pin: _passwordController.text,
        );
      } else {
        await auth.signIn(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onForgotPassword() async {
    final email = _emailController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (validateEmail(email) != null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Type your email above first, then tap this again.'),
        ),
      );
      return;
    }
    try {
      await AuthScope.of(context).sendPasswordReset(email);
      messenger.showSnackBar(
        SnackBar(content: Text('Password reset link sent to $email.')),
      );
    } on AuthFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _setMode(_LoginMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
      _passwordController.clear();
    });
    _formKey.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isManager = _mode == _LoginMode.manager;
    final secretLabel = isManager ? 'PIN' : 'Password';
    final secretName = isManager ? 'PIN' : 'password';
    // After a successful login the profile is still loading for a moment.
    final busy = _busy || AuthScope.of(context).session is SessionLoading;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Column(
          children: [
            const BrandHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Welcome back',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SegmentedButton<_LoginMode>(
                          segments: const [
                            ButtonSegment(
                              value: _LoginMode.manager,
                              label: Text('Manager'),
                              icon: Icon(Icons.badge_outlined),
                            ),
                            ButtonSegment(
                              value: _LoginMode.ceo,
                              label: Text('CEO'),
                              icon: Icon(Icons.business_center_outlined),
                            ),
                          ],
                          selected: {_mode},
                          showSelectedIcon: false,
                          onSelectionChanged: busy
                              ? null
                              : (selection) => _setMode(selection.first),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isManager
                              ? 'Log in with the company code, username and '
                                    'PIN your CEO gave you.'
                              : 'Log in with your email and password.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (isManager) ...[
                          TextFormField(
                            key: const ValueKey('company-code'),
                            controller: _codeController,
                            enabled: !busy,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            validator: validateCompanyCode,
                            decoration: const InputDecoration(
                              labelText: 'Company code',
                              prefixIcon: Icon(Icons.apartment_outlined),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const ValueKey('username'),
                            controller: _usernameController,
                            enabled: !busy,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.username],
                            validator: validateUsername,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                        ] else
                          TextFormField(
                            key: const ValueKey('email'),
                            controller: _emailController,
                            enabled: !busy,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            validator: validateEmail,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: ValueKey(secretLabel),
                          controller: _passwordController,
                          enabled: !busy,
                          obscureText: _hidePassword,
                          keyboardType: isManager
                              ? TextInputType.number
                              : TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          validator: (value) => (value ?? '').isEmpty
                              ? 'Enter your $secretName'
                              : null,
                          onFieldSubmitted: (_) => _onLogin(),
                          decoration: InputDecoration(
                            labelText: secretLabel,
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _hidePassword
                                  ? 'Show $secretName'
                                  : 'Hide $secretName',
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _hidePassword = !_hidePassword,
                              ),
                            ),
                          ),
                        ),
                        if (isManager)
                          const SizedBox(height: 24)
                        else
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: busy ? null : _onForgotPassword,
                              child: const Text('Forgot password?'),
                            ),
                          ),
                        if (_error != null) ...[
                          ErrorBanner(message: _error!),
                          const SizedBox(height: 16),
                        ],
                        FilledButton(
                          onPressed: busy ? null : _onLogin,
                          child: busy
                              ? const SizedBox.square(
                                  dimension: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text('Log in'),
                        ),
                        const SizedBox(height: 32),
                        const Divider(),
                        const SizedBox(height: 16),
                        Text(
                          'Setting up for a new firm?',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () => context.push(AppRoutes.signup),
                          icon: const Icon(Icons.add_business_outlined),
                          label: const Text('Create a company account'),
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
