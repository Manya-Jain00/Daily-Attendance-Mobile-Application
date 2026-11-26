import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/phone_number.dart';
import '../../shared/widgets/brand_header.dart';
import '../../shared/widgets/error_banner.dart';
import 'auth_scope.dart';
import 'auth_service.dart';
import 'form_validators.dart';

/// Everyone logs in the same way: mobile number, then the code sent to it by
/// SMS. Whether they're a director or a manager comes from their profile.
/// A number that isn't in any company yet is offered to set one up.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _resendWait = 30;

  final _phoneFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  /// Set once a code has been sent: the screen then asks for the code.
  CodeSent? _sent;
  bool _busy = false;
  String? _error;

  Timer? _resendTimer;
  int _resendIn = 0;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode({bool again = false}) async {
    if (_busy) return;
    if (!again && !_phoneFormKey.currentState!.validate()) return;
    final phone = PhoneNumber.normalize(_phoneController.text)!;
    await _run(() async {
      final sent = await AuthScope.of(context)
          .sendCode(phone, resend: again ? _sent : null);
      // Null: the phone confirmed the number itself and is logging in; the
      // router moves on by itself.
      if (sent == null || !mounted) return;
      setState(() {
        _sent = sent;
        _codeController.clear();
      });
      _startResendTimer();
    });
  }

  Future<void> _confirm() async {
    final sent = _sent;
    if (_busy || sent == null || !_codeFormKey.currentState!.validate()) {
      return;
    }
    // On success the router moves on to the right screen by itself.
    await _run(
      () => AuthScope.of(context).confirmCode(sent, _codeController.text),
    );
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendIn = _resendWait);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  void _changeNumber() {
    _resendTimer?.cancel();
    setState(() {
      _sent = null;
      _error = null;
      _resendIn = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                child: _sent == null
                    ? _buildPhoneStep(context, busy)
                    : _buildCodeStep(context, busy, _sent!),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneStep(BuildContext context, bool busy) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Form(
      key: _phoneFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Welcome',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Log in with your mobile number. We will send you a code by SMS.',
            style: muted,
          ),
          const SizedBox(height: 24),
          TextFormField(
            key: const ValueKey('phone'),
            controller: _phoneController,
            enabled: !busy,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
              LengthLimitingTextInputFormatter(16),
            ],
            validator: validatePhone,
            onFieldSubmitted: (_) => _sendCode(),
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              prefixText: '${PhoneNumber.defaultCountryCode} ',
              prefixIcon: Icon(Icons.phone_android_outlined),
            ),
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: 16),
          ],
          FilledButton(
            onPressed: busy ? null : _sendCode,
            child: busy ? const _Spinner() : const Text('Send code'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Setting up for a new firm? Log in with your number and you can '
            'create your company next.',
            style: muted,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCodeStep(BuildContext context, bool busy, CodeSent sent) {
    final theme = Theme.of(context);
    return Form(
      key: _codeFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter the code',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We sent a ${PhoneNumber.codeLength}-digit code to '
            '${PhoneNumber.format(sent.phone)}.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextFormField(
            key: const ValueKey('sms-code'),
            controller: _codeController,
            enabled: !busy,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(PhoneNumber.codeLength),
            ],
            validator: validateSmsCode,
            onFieldSubmitted: (_) => _confirm(),
            decoration: const InputDecoration(
              labelText: 'Code',
              prefixIcon: Icon(Icons.sms_outlined),
            ),
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[
            ErrorBanner(message: _error!),
            const SizedBox(height: 16),
          ],
          FilledButton(
            onPressed: busy ? null : _confirm,
            child: busy ? const _Spinner() : const Text('Log in'),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: busy ? null : _changeNumber,
                child: const Text('Change number'),
              ),
              TextButton(
                onPressed: busy || _resendIn > 0
                    ? null
                    : () => _sendCode(again: true),
                child: Text(
                  _resendIn > 0 ? 'Send again in ${_resendIn}s' : 'Send again',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 24,
    child: CircularProgressIndicator(strokeWidth: 2.5),
  );
}
