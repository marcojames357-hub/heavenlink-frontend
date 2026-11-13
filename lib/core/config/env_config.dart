import 'package:flutter/foundation.dart';

/// Compile-time environment configuration for Haven Link.
///
/// Values are injected with `--dart-define` / `--dart-define-from-file` so no
/// secret credential is ever committed to frontend source:
///
/// ```powershell
/// flutter run --dart-define=HAVEN_API_BASE_URL=https://api.example.co.tz
/// ```
///
/// Everything that talks to an external provider (SMS OTP, mobile money,
/// cards) is off until the matching value is provided. See
/// `docs/BACKEND_SETUP.md` for the required backend endpoints.
class EnvConfig {
  const EnvConfig._();

  // ---------------------------------------------------------------------------
  // Backend
  // ---------------------------------------------------------------------------

  /// Base URL of the Haven Link backend. Empty means "not configured".
  static const String apiBaseUrl = String.fromEnvironment('HAVEN_API_BASE_URL');

  /// Explicitly labelled isolated local demo build; never a production default.
  static const bool demoMode = bool.fromEnvironment(
    'HAVEN_DEMO_MODE',
    defaultValue: false,
  );

  /// True when a backend has been supplied at build time.
  static bool get backendConfigured => apiBaseUrl.isNotEmpty;

  static Uri endpoint(String path) {
    final base = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;
    return Uri.parse('$base$path');
  }

  // ---------------------------------------------------------------------------
  // SMS one-time-password policy (server enforces these as well)
  // ---------------------------------------------------------------------------

  /// Seconds the user must wait before requesting another code.
  static const int resendCooldownSeconds = int.fromEnvironment(
    'HAVEN_OTP_RESEND_COOLDOWN',
    defaultValue: 45,
  );

  /// Seconds before a challenge expires.
  static const int codeExpirySeconds = int.fromEnvironment(
    'HAVEN_OTP_CODE_TTL',
    defaultValue: 300,
  );

  /// Wrong-code attempts allowed before a challenge is locked.
  static const int maxVerifyAttempts = int.fromEnvironment(
    'HAVEN_OTP_MAX_ATTEMPTS',
    defaultValue: 5,
  );

  /// Resend requests allowed for a single phone number inside the window.
  static const int maxResends = int.fromEnvironment(
    'HAVEN_OTP_MAX_RESENDS',
    defaultValue: 5,
  );

  /// Label of the connected SMS provider, shown in the UI when set.
  static const String smsProviderLabel = String.fromEnvironment(
    'HAVEN_SMS_PROVIDER',
    defaultValue: '',
  );

  // ---------------------------------------------------------------------------
  // Payment providers
  // ---------------------------------------------------------------------------

  /// Comma separated list of configured providers, e.g. `mpesa,airtel,tigopesa,card`.
  /// A method is never offered to customers until it appears here.
  static const String configuredPaymentMethods = String.fromEnvironment(
    'HAVEN_PAYMENT_METHODS',
    defaultValue: '',
  );

  static Set<String> get enabledPaymentMethodIds => configuredPaymentMethods
      .split(',')
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();

  static bool get paymentsConfigured => enabledPaymentMethodIds.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Development-only preview switches
  //
  // These exist so the OTP and payment *flows* can be exercised before the
  // real providers are connected. They are compiled out of release builds and
  // the UI shows a persistent preview banner while active. They must never be
  // presented as production verification or payment.
  // ---------------------------------------------------------------------------

  static const bool _previewOtpFlag = bool.fromEnvironment(
    'HAVEN_PREVIEW_OTP',
    defaultValue: true,
  );

  static const bool _previewPaymentFlag = bool.fromEnvironment(
    'HAVEN_PREVIEW_PAYMENTS',
    defaultValue: true,
  );

  /// Local OTP challenges are only possible in debug builds.
  static bool get previewOtpEnabled => kDebugMode && _previewOtpFlag;

  /// Local payment simulation is only possible in debug builds.
  static bool get previewPaymentsEnabled => kDebugMode && _previewPaymentFlag;

  /// True when no real SMS service is reachable and the preview stand-in is
  /// being used instead. The UI must surface this clearly.
  static bool get otpRunningInPreview =>
      !backendConfigured && previewOtpEnabled;

  static bool get paymentsRunningInPreview =>
      !paymentsConfigured && previewPaymentsEnabled;
}
