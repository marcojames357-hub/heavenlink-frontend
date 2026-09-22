import 'package:flutter/material.dart';

import '../../../core/config/env_config.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/domain/account_models.dart';
import '../domain/otp_verification_service.dart';
import '../domain/phone_number.dart';
import 'phone_verification/otp_verification_screen.dart';

/// Sign-in and registration.
///
/// Registration is a two-step flow: details first, then phone verification.
/// The account is only created once `OtpVerificationService.verify` succeeds,
/// so an unverified number never produces an account. No document upload is
/// part of this flow.
class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.store, super.key});

  final HavenLinkStore store;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _register = false;
  bool _busy = false;
  String? _error;
  AccountRole _role = AccountRole.customer;
  late String _sessionId;

  OtpVerificationService get _otp => widget.store.otpService;

  @override
  void initState() {
    super.initState();
    _sessionId = 'sess-${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Haven Link account')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 470),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.home_work_outlined,
                        color: HavenTheme.teal,
                        size: 42,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _register ? 'Create your account' : 'Welcome back',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _register
                            ? 'Verify your phone number to finish. No documents '
                                  'are required to register.'
                            : 'Sign in to keep bookings, saved homes and '
                                  'unlocked contacts together.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: HavenTheme.muted,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _ServiceBanner(service: _otp),
                      const SizedBox(height: 16),
                      if (_register) ...[
                        _AccountTypePicker(
                          value: _role,
                          onChanged: (role) => setState(() => _role = role),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                          ),
                          validator: (value) =>
                              value == null || value.trim().length < 2
                              ? 'Enter your name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                        ),
                        validator: (value) =>
                            value == null ||
                                !RegExp(
                                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                ).hasMatch(value)
                            ? 'Enter a valid email address'
                            : null,
                      ),
                      if (_register) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          decoration: const InputDecoration(
                            labelText: 'Phone number',
                            hintText: '0754 123 456',
                          ),
                          validator: (value) =>
                              TanzanianPhone.tryNormalize(value ?? '') == null
                              ? 'Enter a valid Tanzanian mobile number'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: const InputDecoration(
                            labelText: 'Create password',
                          ),
                          validator: (value) =>
                              value == null || value.length < 8
                              ? 'Use at least 8 characters'
                              : null,
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                          validator: (value) =>
                              value == null || value.length < 8
                              ? 'Enter your password'
                              : null,
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : (_register ? _sendCode : _signIn),
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                _register ? Icons.sms_outlined : Icons.login,
                              ),
                        label: Text(
                          _busy
                              ? 'Please wait'
                              : _register
                              ? 'Send Verification Code'
                              : 'Sign in',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _register = !_register;
                                _error = null;
                              }),
                        child: Text(
                          _register
                              ? 'Already have an account? Sign in'
                              : 'New to Haven Link? Create an account',
                        ),
                      ),
                      const Divider(height: 26),
                      const Text(
                        'Haven Link never asks for an authorization letter, '
                        'title deed or other documents to register. Phone '
                        'verification confirms access to a number — it is not '
                        'proof of property ownership.',
                        style: TextStyle(
                          color: HavenTheme.muted,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _sendCode() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = TanzanianPhone.tryNormalize(_phoneController.text);
    if (phone == null) {
      setState(() => _error = 'Enter a valid Tanzanian mobile number.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final challenge = await _otp.requestCode(
        phoneE164: phone,
        sessionId: _sessionId,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      final verifiedChallenge = await Navigator.of(context).push<OtpChallenge>(
        MaterialPageRoute<OtpChallenge>(
          builder: (context) => OtpVerificationScreen(
            service: _otp,
            challenge: challenge,
            onEditPhone: () => Navigator.of(context).pop(),
            onVerified: (challenge) => Navigator.of(context).pop(challenge),
          ),
        ),
      );
      if (verifiedChallenge == null || !mounted) return;
      await _completeRegistration(phone, verifiedChallenge);
    } on OtpException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'We could not send a code right now. Try again shortly.';
      });
    }
  }

  /// Runs only after the verification service accepted the code.
  Future<void> _completeRegistration(
    String phoneE164,
    OtpChallenge challenge,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final capabilities = _role == AccountRole.rentalAgent
          ? {AgentCapability.rentalProperty}
          : _role == AccountRole.stayAgent
          ? {AgentCapability.accommodationBooking}
          : <AgentCapability>{};
      await widget.store.register(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phoneE164: phoneE164,
        password: _passwordController.text,
        challengeId: challenge.challengeId,
        sessionId: challenge.sessionId,
        role: _role,
        capabilities: capabilities,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString();
      });
    }
  }
}

/// Explains which verification service this build is actually using.
class _ServiceBanner extends StatelessWidget {
  const _ServiceBanner({required this.service});

  final OtpVerificationService service;

  @override
  Widget build(BuildContext context) {
    if (EnvConfig.otpRunningInPreview) {
      return const _Banner(
        icon: Icons.science_outlined,
        text:
            'PREVIEW: no SMS provider is connected. Codes are generated on '
            'this device for development only and are never real messages.',
      );
    }
    if (!service.isConfigured) {
      return const _Banner(
        icon: Icons.cloud_off_outlined,
        text:
            'SMS verification is not configured yet. Registration stays '
            'disabled until a backend and SMS provider are connected '
            '(see docs/BACKEND_SETUP.md).',
      );
    }
    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HavenTheme.lightMint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HavenTheme.mint),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: HavenTheme.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lets the applicant pick the service they are registering for. The choice
/// only sets a requested role — the server issues the authoritative role.
class _AccountTypePicker extends StatelessWidget {
  const _AccountTypePicker({required this.value, required this.onChanged});

  final AccountRole value;
  final ValueChanged<AccountRole> onChanged;

  static const List<(AccountRole, String, IconData)> _options = [
    (AccountRole.customer, 'Customer', Icons.person_outline),
    (
      AccountRole.rentalAgent,
      'Rental property agent',
      Icons.home_work_outlined,
    ),
    (AccountRole.stayAgent, 'Stay agent', Icons.hotel_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'I am registering as',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _options
              .map(
                (option) => ChoiceChip(
                  label: Text(option.$2),
                  avatar: Icon(option.$3, size: 16),
                  selected: value == option.$1,
                  onSelected: (_) => onChanged(option.$1),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
