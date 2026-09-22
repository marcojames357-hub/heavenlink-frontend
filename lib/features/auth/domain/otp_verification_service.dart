/// A pending one-time-password challenge.
///
/// The challenge is bound to [phoneE164] and to the authentication [sessionId]
/// that requested it; the server rejects a code presented against a different
/// destination or session.
class OtpChallenge {
  const OtpChallenge({
    required this.challengeId,
    required this.phoneE164,
    required this.sessionId,
    required this.issuedAt,
    required this.expiresAt,
    required this.resendAvailableAt,
    required this.attemptsRemaining,
    required this.resendCount,
    this.debugCode,
  });

  final String challengeId;
  final String phoneE164;
  final String sessionId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final DateTime resendAvailableAt;
  final int attemptsRemaining;
  final int resendCount;

  /// Only ever populated by the local development stand-in. A real SMS
  /// provider never returns the code, and the UI renders it exclusively in
  /// debug builds so nobody can mistake preview mode for delivery.
  final String? debugCode;

  bool isExpired([DateTime? now]) =>
      (now ?? DateTime.now()).isAfter(expiresAt);

  bool canResend([DateTime? now]) =>
      (now ?? DateTime.now()).isAfter(resendAvailableAt) ||
      (now ?? DateTime.now()).isAtSameMomentAs(resendAvailableAt);

  Duration get resendIn => resendAvailableAt.difference(DateTime.now());
}

/// Every failure the OTP flow can produce, mapped to user-facing wording.
sealed class OtpException implements Exception {
  const OtpException({required this.message});

  final String message;

  @override
  String toString() => message;
}

/// No SMS provider and no backend URL are configured.
class OtpNotConfiguredException extends OtpException {
  const OtpNotConfiguredException({
    super.message =
        'SMS verification is not configured yet. Set HAVEN_API_BASE_URL and '
        'connect an SMS provider before enabling registration.',
  });
}

/// The code did not match.
class OtpInvalidCodeException extends OtpException {
  const OtpInvalidCodeException({
    this.attemptsRemaining = 0,
    super.message = 'That code is not correct. Check the message and try again.',
  });

  final int attemptsRemaining;
}

/// The code passed its expiry window.
class OtpExpiredCodeException extends OtpException {
  const OtpExpiredCodeException({
    super.message = 'This code has expired. Request a new one.',
  });
}

/// Too many wrong attempts — the challenge is locked.
class OtpTooManyAttemptsException extends OtpException {
  const OtpTooManyAttemptsException({
    super.message = 'Too many incorrect attempts. Request a new code.',
  });
}

/// Resend or request throttling, with the server-mandated wait.
class OtpRateLimitedException extends OtpException {
  const OtpRateLimitedException({
    this.retryAfter = const Duration(seconds: 45),
    super.message = 'Please wait before requesting another code.',
  });

  final Duration retryAfter;
}

/// Transport failure — nothing was verified.
class OtpNetworkException extends OtpException {
  const OtpNetworkException({
    super.message =
        'We could not reach the verification service. Check your connection '
        'and try again.',
  });
}

/// The challenge no longer belongs to this session or destination.
class OtpSessionMismatchException extends OtpException {
  const OtpSessionMismatchException({
    super.message = 'This verification request is no longer valid.',
  });
}

/// Contract every OTP backend must satisfy.
///
/// Implementation lives on the server or with the SMS provider: codes,
/// provider credentials, expiry, attempt limits and resend limits never live
/// in the app.
abstract interface class OtpVerificationService {
  /// Human-readable provider name for the UI.
  String get providerLabel;

  /// True when a real SMS can actually be sent right now.
  bool get isConfigured;

  /// Starts a challenge for [phoneE164], bound to [sessionId].
  Future<OtpChallenge> requestCode({
    required String phoneE164,
    required String sessionId,
  });

  /// Requests a replacement code for an existing challenge, subject to the
  /// resend cooldown and resend limit.
  Future<OtpChallenge> resendCode({
    required String challengeId,
    required String sessionId,
  });

  /// Confirms the code. Throws an [OtpException] on any failure; the phone
  /// number may only be marked verified when this completes normally.
  Future<void> verify({
    required String challengeId,
    required String phoneE164,
    required String sessionId,
    required String code,
  });
}
