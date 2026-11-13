import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/config/env_config.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/domain/account_models.dart';
import 'workspace_selection.dart';
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
  const AuthScreen({
    required this.store,
    this.initialRegister = false,
    super.key,
  });

  final HavenLinkStore store;
  final bool initialRegister;

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
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;
  _RegistrationType _registrationType = _RegistrationType.customer;
  Set<AgentWorkspace> _additionalWorkspaces = {};
  late String _sessionId;

  OtpVerificationService get _otp => widget.store.otpService;

  @override
  void initState() {
    super.initState();
    _register = widget.initialRegister;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1024;
        final form = Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(wide ? 40 : 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: EdgeInsets.all(wide ? 32 : 24),
                decoration: BoxDecoration(
                  color: HavenTheme.white,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: HavenTheme.border),
                  boxShadow: [
                    BoxShadow(
                      color: HavenTheme.darkTeal.withValues(alpha: .10),
                      blurRadius: 70,
                      offset: const Offset(0, 24),
                    ),
                  ],
                ),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!wide) ...[
                          Row(
                            children: [
                              const Expanded(child: _AuthBrand()),
                              if (Navigator.of(context).canPop())
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: Text(context.tr('Back home')),
                                ),
                            ],
                          ),
                          const SizedBox(height: 28),
                        ] else if (Navigator.of(context).canPop()) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: IconButton(
                              tooltip: context.tr('Back'),
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(HavenIcons.arrowBack, size: 18),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDF4F2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              for (final option in [false, true])
                                Expanded(
                                  child: TextButton(
                                    key: Key(
                                      option
                                          ? 'auth-mode-register'
                                          : 'auth-mode-login',
                                    ),
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() {
                                            _register = option;
                                            _obscurePassword = true;
                                            _error = null;
                                          }),
                                    style: TextButton.styleFrom(
                                      backgroundColor: _register == option
                                          ? HavenTheme.white
                                          : Colors.transparent,
                                      foregroundColor: _register == option
                                          ? HavenTheme.forest
                                          : HavenTheme.muted,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      textStyle: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    child: Text(
                                      context.tr(
                                        option ? 'Create account' : 'Log in',
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          context.tr(
                            _register ? 'Join Haven Link' : 'Welcome back',
                          ),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontSize: 24,
                                letterSpacing: -.8,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr(
                            _register
                                ? 'Create your identity and choose the workspace you need.'
                                : 'Sign in to continue to your authorized workspace.',
                          ),
                          style: const TextStyle(
                            color: HavenTheme.muted,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_register) ...[
                          _AuthField(
                            label: context.tr('Full name'),
                            child: TextFormField(
                              key: const Key('auth-full-name'),
                              controller: _nameController,
                              textCapitalization: TextCapitalization.words,
                              autofillHints: const [AutofillHints.name],
                              decoration: _input('Amina Mussa'),
                              textInputAction: TextInputAction.next,
                              validator: (value) =>
                                  value == null || value.trim().length < 2
                                  ? context.tr('Enter your name')
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _AuthField(
                          label: context.tr('Email address'),
                          child: TextFormField(
                            key: const Key('auth-email'),
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: _input('you@example.com'),
                            textInputAction: TextInputAction.next,
                            validator: (value) =>
                                value == null ||
                                    !RegExp(
                                      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                    ).hasMatch(value)
                                ? context.tr('Enter a valid email address')
                                : null,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_register) ...[
                          _AuthField(
                            label: context.tr('Phone number'),
                            child: TextFormField(
                              key: const Key('auth-phone'),
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              autofillHints: const [
                                AutofillHints.telephoneNumber,
                              ],
                              decoration: _input('+255 7XX XXX XXX'),
                              textInputAction: TextInputAction.next,
                              validator: (value) =>
                                  TanzanianPhone.tryNormalize(value ?? '') ==
                                      null
                                  ? context.tr(
                                      'Enter a valid Tanzanian mobile number',
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _AuthField(
                          label: context.tr('Password'),
                          child: TextFormField(
                            key: const Key('auth-password'),
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            autofillHints: [
                              _register
                                  ? AutofillHints.newPassword
                                  : AutofillHints.password,
                            ],
                            decoration:
                                _input(
                                  context.tr('At least 8 characters'),
                                ).copyWith(
                                  suffixIcon: IconButton(
                                    tooltip: context.tr(
                                      _obscurePassword
                                          ? 'Show password'
                                          : 'Hide password',
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? HavenIcons.visibilityOutlined
                                          : HavenIcons.visibilityOffOutlined,
                                      size: 18,
                                    ),
                                  ),
                                ),
                            onFieldSubmitted: (_) {
                              if (!_busy) {
                                _register ? _sendCode() : _signIn();
                              }
                            },
                            validator: (value) =>
                                value == null || value.length < 8
                                ? context.tr(
                                    _register
                                        ? 'Use at least 8 characters'
                                        : 'Enter your password',
                                  )
                                : null,
                          ),
                        ),
                        if (_register) ...[
                          const SizedBox(height: 16),
                          _AuthField(
                            label: context.tr('I am registering as'),
                            child: DropdownButtonFormField<_RegistrationType>(
                              key: const Key('auth-registration-type'),
                              initialValue: _registrationType,
                              isExpanded: true,
                              decoration: _input(''),
                              items: [
                                for (final option in _RegistrationType.values)
                                  DropdownMenuItem(
                                    value: option,
                                    child: Text(
                                      context.tr(option.label),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        setState(() {
                                          _registrationType = value;
                                          _additionalWorkspaces = {};
                                        });
                                      }
                                    },
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.tr(
                              _additionalWorkspaces.length > 1
                                  ? _additionalWorkspaces
                                        .map((workspace) => workspace.title)
                                        .join(' ? ')
                                  : 'Partner workspaces are activated after Haven Link verification.',
                            ),
                            style: const TextStyle(
                              color: HavenTheme.muted,
                              fontSize: 11,
                              height: 1.45,
                            ),
                          ),
                          if (_registrationType.workspace != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: _busy
                                    ? null
                                    : _chooseAdditionalWorkspaces,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  textStyle: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                child: Text(
                                  context.tr(
                                    _additionalWorkspaces.length > 1
                                        ? 'Manage selected workspaces'
                                        : 'Manage more than one property type',
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          _ServiceBanner(service: _otp),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          _Banner(icon: HavenIcons.errorOutline, text: _error!),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          key: const Key('auth-submit'),
                          onPressed: _busy
                              ? null
                              : (_register ? _sendCode : _signIn),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          iconAlignment: IconAlignment.end,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: HavenTheme.white,
                                  ),
                                )
                              : const Icon(HavenIcons.shieldOutlined, size: 17),
                          label: Text(
                            context.tr(
                              _busy
                                  ? 'Please wait'
                                  : _register
                                  ? 'Create secure account'
                                  : 'Log in securely',
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          context.tr(
                            'By continuing, you agree to Haven Link\u2019s terms and privacy policy.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: HavenTheme.muted,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                        if (_register) ...[
                          const SizedBox(height: 10),
                          Text(
                            context.tr(
                              'Phone verification is required to complete registration.',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: HavenTheme.muted,
                              fontSize: 11,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return Scaffold(
          backgroundColor: HavenTheme.veryLightMint,
          body: wide
              ? Row(
                  children: [
                    const Expanded(flex: 9, child: _AuthBrandPanel()),
                    Expanded(flex: 11, child: form),
                  ],
                )
              : SafeArea(child: form),
        );
      },
    );
  }

  InputDecoration _input(String hint) => InputDecoration(
    hintText: hint,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    hintStyle: const TextStyle(color: HavenTheme.muted, fontSize: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: HavenTheme.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: HavenTheme.border),
    ),
  );

  Future<void> _chooseAdditionalWorkspaces() async {
    final chosen = await showWorkspaceSelection(
      context,
      initialSelection: _additionalWorkspaces.isEmpty
          ? {_registrationType.workspace!}
          : _additionalWorkspaces,
    );
    if (!mounted || chosen == null || chosen.isEmpty) return;
    setState(() {
      _additionalWorkspaces = chosen;
      if (!chosen.contains(_registrationType.workspace)) {
        _registrationType = _RegistrationType.values.firstWhere(
          (type) => type.workspace == chosen.first,
        );
      }
    });
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await widget.store.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(user);
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
      setState(
        () => _error = context.tr('Enter a valid Tanzanian mobile number.'),
      );
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
        _error = context.tr(
          'We could not send a code right now. Try again shortly.',
        );
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
      final workspaces = _additionalWorkspaces.isNotEmpty
          ? {..._additionalWorkspaces}
          : <AgentWorkspace>{
              if (_registrationType.workspace != null)
                _registrationType.workspace!,
            };
      final role = workspaces.isEmpty
          ? AccountRole.customer
          : workspaces.length == 1 && workspaces.contains(AgentWorkspace.rental)
          ? AccountRole.rentalAgent
          : AccountRole.stayAgent;
      final capabilities = <AgentCapability>{
        if (workspaces.contains(AgentWorkspace.rental))
          AgentCapability.rentalProperty,
        if (workspaces.contains(AgentWorkspace.apartment) ||
            workspaces.contains(AgentWorkspace.hotel))
          AgentCapability.accommodationBooking,
      };
      final user = await widget.store.register(
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phoneE164: phoneE164,
        password: _passwordController.text,
        challengeId: challenge.challengeId,
        sessionId: challenge.sessionId,
        role: role,
        capabilities: capabilities,
        workspaces: workspaces,
      );
      if (!mounted) return;
      Navigator.of(context).pop(user);
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
      return _Banner(
        icon: HavenIcons.scienceOutlined,
        text: context.tr(
          'PREVIEW: no SMS provider is connected. Codes are generated on this device for development only and are never real messages.',
        ),
      );
    }
    if (!service.isConfigured) {
      return _Banner(
        icon: HavenIcons.cloudOffOutlined,
        text: context.tr(
          'SMS verification is not configured yet. Registration stays disabled until a backend and SMS provider are connected (see docs/BACKEND_SETUP.md).',
        ),
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

enum _RegistrationType {
  customer('Customer', null),
  rental('Rental Agent', AgentWorkspace.rental),
  apartment('Apartment Stays Agent', AgentWorkspace.apartment),
  hotel('Hotel, Lodge & Motel Agent', AgentWorkspace.hotel);

  const _RegistrationType(this.label, this.workspace);
  final String label;
  final AgentWorkspace? workspace;
}

class _AuthField extends StatelessWidget {
  const _AuthField({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: HavenTheme.darkTeal,
          fontSize: 10,
          letterSpacing: .6,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      Semantics(label: label, child: child),
    ],
  );
}

class _AuthBrand extends StatelessWidget {
  const _AuthBrand({this.light = false});
  final bool light;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => Navigator.of(context).maybePop(),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: light ? HavenTheme.white : HavenTheme.forest,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
              bottomRight: Radius.circular(14),
              bottomLeft: Radius.circular(5),
            ),
          ),
          child: Icon(
            HavenIcons.homeRounded,
            color: light ? HavenTheme.forest : HavenTheme.white,
            size: 21,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Haven Link',
          style: TextStyle(
            color: light ? HavenTheme.white : HavenTheme.ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -.6,
          ),
        ),
      ],
    ),
  );
}

class _AuthBrandPanel extends StatelessWidget {
  const _AuthBrandPanel();

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AuthBrand(light: true),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 512),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('One secure account').toUpperCase(),
                    style: const TextStyle(
                      color: HavenTheme.mintAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('Every property journey. One trusted identity.'),
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: HavenTheme.white,
                      fontSize: 46,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    context.tr(
                      'Book verified stays, unlock rental contacts, or request an approved partner workspace.',
                    ),
                    style: TextStyle(
                      color: HavenTheme.white.withValues(alpha: .78),
                      fontSize: 14,
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 36),
                  for (final label in [
                    'Secure account and payment records',
                    'Role-based workspace routing',
                    'Verified property and agent network',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          const Icon(
                            HavenIcons.checkCircleOutline,
                            size: 18,
                            color: HavenTheme.mintAccent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              context.tr(label),
                              style: TextStyle(
                                color: HavenTheme.white.withValues(alpha: .87),
                                fontSize: 12,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text(
            'Haven Link \u00b7 Tanzania \u00b7 English / Kiswahili ready',
            style: TextStyle(
              color: HavenTheme.white.withValues(alpha: .6),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        color: HavenTheme.darkTeal,
        child: Stack(
          children: [
            Positioned(
              top: -180,
              right: -220,
              child: Container(
                width: 600,
                height: 600,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      HavenTheme.forest.withValues(alpha: .45),
                      HavenTheme.forest.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(child: content),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
