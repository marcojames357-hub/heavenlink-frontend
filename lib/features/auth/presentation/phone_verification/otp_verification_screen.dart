import 'dart:async';

import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';
import 'package:flutter/services.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/otp_verification_service.dart';
import '../../domain/phone_number.dart';

/// Code-entry step of phone verification.
///
/// Shows the destination the code was sent to (with a way to correct it),
/// accepts automatic SMS autofill where the platform provides it plus manual
/// entry everywhere, enforces the resend countdown, and surfaces invalid,
/// expired, rate-limited and network failures without ever marking the number
/// verified on failure.
class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    required this.service,
    required this.challenge,
    required this.onVerified,
    required this.onEditPhone,
    super.key,
  });

  final OtpVerificationService service;
  final OtpChallenge challenge;

  /// Called only after the verification service accepted the code.
  final ValueChanged<OtpChallenge> onVerified;

  /// Lets the user correct the destination number.
  final VoidCallback onEditPhone;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  static const int _codeLength = 6;

  final _codeController = TextEditingController();
  final _focusNode = FocusNode();
  late OtpChallenge _challenge;
  Timer? _ticker;

  bool _verifying = false;
  bool _resending = false;
  bool _success = false;
  String? _error;
  int _secondsLeft = 0;

  bool get _previewMode => EnvConfig.otpRunningInPreview && _debugCode != null;

  String? get _debugCode => _challenge.debugCode;

  @override
  void initState() {
    super.initState();
    _challenge = widget.challenge;
    _secondsLeft = _remainingSeconds(_challenge);
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _secondsLeft = _remainingSeconds(_challenge));
      if (_secondsLeft <= 0) timer.cancel();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      TextInput.finishAutofillContext();
    });
  }

  int _remainingSeconds(OtpChallenge challenge) {
    final left = challenge.resendAvailableAt
        .difference(DateTime.now())
        .inSeconds;
    return left > 0 ? left : 0;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _displayPhone =>
      TanzanianPhone.formatForDisplay(_challenge.phoneE164);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Verify your phone'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 470),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      HavenIcons.smsOutlined,
                      color: HavenTheme.teal,
                      size: 42,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      context.tr('Enter the 6-digit code'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        text: context.tr('We sent a code to '),
                        children: [
                          TextSpan(
                            text: _displayPhone,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: HavenTheme.muted,
                        height: 1.45,
                      ),
                    ),
                    TextButton(
                      onPressed: _verifying ? null : widget.onEditPhone,
                      child: Text(context.tr('Not your number? Change it')),
                    ),
                    if (_previewMode) ...[
                      const SizedBox(height: 4),
                      _PreviewCodeBanner(code: _debugCode!),
                    ],
                    const SizedBox(height: 18),
                    TextField(
                      controller: _codeController,
                      focusNode: _focusNode,
                      maxLength: _codeLength,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(_codeLength),
                      ],
                      decoration: InputDecoration(
                        labelText: context.tr('Verification code'),
                        hintText: '123456',
                        counterText: '',
                      ),
                      onSubmitted: (_) => _verify(),
                      onChanged: (value) {
                        if (_error != null) setState(() => _error = null);
                        if (value.length == _codeLength) _verify();
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
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
                      onPressed: _verifying || _success ? null : _verify,
                      icon: _verifying || _success
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(HavenIcons.checkCircleOutline),
                      label: Text(
                        _success
                            ? context.tr('Phone verified')
                            : _verifying
                            ? context.tr('Verifying…')
                            : context.tr('Verify phone number'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _resendButton(),
                    const SizedBox(height: 6),
                    Text(
                      '${context.tr('Provider')}: ${widget.service.providerLabel}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: HavenTheme.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resendButton() {
    if (_secondsLeft > 0) {
      return Text(
        '${context.tr('Resend available in')} ${_secondsLeft}s',
        textAlign: TextAlign.center,
        style: const TextStyle(color: HavenTheme.muted),
      );
    }
    return TextButton.icon(
      onPressed: _resending ? null : _resend,
      icon: _resending
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(HavenIcons.refresh, size: 17),
      label: Text(context.tr('Resend code')),
    );
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final next = await widget.service.resendCode(
        challengeId: _challenge.challengeId,
        sessionId: _challenge.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _challenge = next;
        _secondsLeft = _remainingSeconds(next);
        _codeController.clear();
        _resending = false;
      });
      TextInput.finishAutofillContext();
    } on OtpException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _resending = false;
        if (error is OtpRateLimitedException) {
          _secondsLeft = error.retryAfter.inSeconds;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.tr('Could not resend the code. Try again shortly.');
        _resending = false;
      });
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != _codeLength) {
      setState(() => _error = context.tr('Enter the full 6-digit code.'));
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await widget.service.verify(
        challengeId: _challenge.challengeId,
        phoneE164: _challenge.phoneE164,
        sessionId: _challenge.sessionId,
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _success = true;
      });
      widget.onVerified(_challenge);
    } on OtpException catch (error) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = error.message;
      });
      _codeController.clear();
      _focusNode.requestFocus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = context.tr(
          'Verification failed. Check your connection and try again.',
        );
      });
      _codeController.clear();
    }
  }
}

/// Shows the code the local preview service generated instead of delivering an
/// SMS. Never rendered outside debug builds.
class _PreviewCodeBanner extends StatelessWidget {
  const _PreviewCodeBanner({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HavenTheme.lightMint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HavenTheme.mint),
      ),
      child: Column(
        children: [
          Text(
            context.tr(
              'PREVIEW MODE — no SMS was sent. This code exists only on this device and must never be used in production.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            code,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 6,
              color: HavenTheme.deepTeal,
            ),
          ),
        ],
      ),
    );
  }
}
