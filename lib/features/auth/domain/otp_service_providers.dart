import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env_config.dart';
import 'otp_verification_service.dart';

// -----------------------------------------------------------------------------
// Production implementation
// -----------------------------------------------------------------------------

/// Talks to the Haven Link backend, which owns the SMS provider credentials.
///
/// Nothing here holds a provider secret or a code; the app only ever posts a
/// destination, a session id and the code the user typed.
class HttpOtpVerificationService implements OtpVerificationService {
  HttpOtpVerificationService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  String get providerLabel => EnvConfig.smsProviderLabel.isEmpty
      ? 'Haven Link verification service'
      : EnvConfig.smsProviderLabel;

  @override
  bool get isConfigured => EnvConfig.backendConfigured;

  @override
  Future<OtpChallenge> requestCode({
    required String phoneE164,
    required String sessionId,
  }) async {
    final response = await _post('/api/v1/otp/request', {
      'phoneE164': phoneE164,
      'sessionId': sessionId,
    });
    if (response.statusCode == 429) throw _rateLimited(response);
    if (response.statusCode >= 400) {
      throw const OtpNetworkException(
        message:
            'The verification service rejected this request. Try again shortly.',
      );
    }
    return _challengeFrom(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<OtpChallenge> resendCode({
    required String challengeId,
    required String sessionId,
  }) async {
    final response = await _post('/api/v1/otp/resend', {
      'sessionId': sessionId,
    });
    if (response.statusCode == 429) throw _rateLimited(response);
    if (response.statusCode == 404 || response.statusCode == 410) {
      throw const OtpSessionMismatchException();
    }
    if (response.statusCode >= 400) throw const OtpNetworkException();
    return _challengeFrom(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<void> verify({
    required String challengeId,
    required String phoneE164,
    required String sessionId,
    required String code,
  }) async {
    final response = await _post('/api/v1/otp/verify', {
      'challengeId': challengeId,
      'phoneE164': phoneE164,
      'sessionId': sessionId,
      'code': code,
    });
    switch (response.statusCode) {
      case 200:
      case 204:
        return;
      case 400:
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final remaining = body is Map<String, dynamic>
            ? (body['attemptsRemaining'] as num?)?.toInt() ?? 0
            : 0;
        throw OtpInvalidCodeException(attemptsRemaining: remaining);
      case 401:
      case 403:
      case 404:
        throw const OtpSessionMismatchException();
      case 410:
        throw const OtpExpiredCodeException();
      case 423:
        throw const OtpTooManyAttemptsException();
      case 429:
        throw _rateLimited(response);
      default:
        throw const OtpNetworkException();
    }
  }

  Future<http.Response> _post(String path, Map<String, Object?> body) async {
    try {
      return await _client
          .post(
            EnvConfig.endpoint(path),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const OtpNetworkException();
    }
  }

  OtpRateLimitedException _rateLimited(http.Response response) {
    final header = response.headers['retry-after'];
    final seconds =
        int.tryParse(header ?? '') ?? EnvConfig.resendCooldownSeconds;
    return OtpRateLimitedException(retryAfter: Duration(seconds: seconds));
  }

  OtpChallenge _challengeFrom(Map<String, dynamic> json) {
    final issuedAt =
        DateTime.tryParse(json['issuedAt'] as String? ?? '') ?? DateTime.now();
    final ttl = Duration(
      seconds:
          (json['ttlSeconds'] as num?)?.toInt() ?? EnvConfig.codeExpirySeconds,
    );
    return OtpChallenge(
      challengeId: json['challengeId'] as String,
      phoneE164: json['phone'] as String,
      sessionId: json['sessionId'] as String? ?? '',
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(ttl),
      resendAvailableAt: DateTime.now().add(
        Duration(
          seconds:
              (json['resendAfterSeconds'] as num?)?.toInt() ??
              EnvConfig.resendCooldownSeconds,
        ),
      ),
      attemptsRemaining:
          (json['attemptsRemaining'] as num?)?.toInt() ??
          EnvConfig.maxVerifyAttempts,
      resendCount: (json['resendCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Local, in-memory challenge store used only while the real SMS provider is
/// not connected.
///
/// It enforces the same expiry, attempt, resend-cooldown and resend-limit
/// rules as the server so those states can be exercised in development, but it
/// sends **no** message. `kDebugMode` is asserted at construction so it cannot
/// reach a release build, and the UI shows a preview banner while active.
class PreviewOtpVerificationService implements OtpVerificationService {
  PreviewOtpVerificationService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    assert(
      kDebugMode,
      'PreviewOtpVerificationService must never run outside debug builds.',
    );
  }

  final DateTime Function() _clock;
  final Map<String, _StoredChallenge> _challenges = {};
  final Map<String, int> _resendUsage = {};

  @override
  String get providerLabel => 'Local preview (no SMS sent)';

  @override
  bool get isConfigured => kDebugMode;

  /// Exposed so the debug banner can show the code it never delivered.
  String? debugCodeFor(String challengeId) =>
      kDebugMode ? _challenges[challengeId]?.code : null;

  @override
  Future<OtpChallenge> requestCode({
    required String phoneE164,
    required String sessionId,
  }) async {
    await _latency();
    _enforceRequestLimit(phoneE164);
    final challenge = _store(
      phoneE164: phoneE164,
      sessionId: sessionId,
      code: _generateCode(),
    );
    _resendUsage[phoneE164] = 1;
    return challenge;
  }

  @override
  Future<OtpChallenge> resendCode({
    required String challengeId,
    required String sessionId,
  }) async {
    await _latency();
    final existing = _challenges[challengeId];
    if (existing == null || existing.sessionId != sessionId) {
      throw const OtpSessionMismatchException();
    }
    final usage = _resendUsage[existing.phoneE164] ?? 0;
    if (usage >= EnvConfig.maxResends) {
      throw const OtpRateLimitedException(
        message: 'Resend limit reached for this number. Try again later.',
        retryAfter: Duration(minutes: 10),
      );
    }
    final wait = existing.resendAvailableAt.difference(_clock());
    if (!wait.isNegative && wait > Duration.zero) {
      throw OtpRateLimitedException(retryAfter: wait);
    }
    final challenge = _store(
      phoneE164: existing.phoneE164,
      sessionId: sessionId,
      code: _generateCode(),
    );
    _resendUsage[existing.phoneE164] = usage + 1;
    _challenges.remove(challengeId);
    return challenge;
  }

  @override
  Future<void> verify({
    required String challengeId,
    required String phoneE164,
    required String sessionId,
    required String code,
  }) async {
    await _latency();
    final stored = _challenges[challengeId];
    if (stored == null ||
        stored.phoneE164 != phoneE164 ||
        stored.sessionId != sessionId) {
      throw const OtpSessionMismatchException();
    }
    if (stored.isExpired(_clock())) {
      _challenges.remove(challengeId);
      throw const OtpExpiredCodeException();
    }
    if (stored.attemptsRemaining <= 0) {
      _challenges.remove(challengeId);
      throw const OtpTooManyAttemptsException();
    }
    if (stored.code != code.trim()) {
      stored.attemptsRemaining -= 1;
      final exhausted = stored.attemptsRemaining <= 0;
      if (exhausted) _challenges.remove(challengeId);
      throw OtpInvalidCodeException(
        attemptsRemaining: stored.attemptsRemaining,
      );
    }
    _challenges.remove(challengeId);
  }

  OtpChallenge _store({
    required String phoneE164,
    required String sessionId,
    required String code,
  }) {
    final issuedAt = _clock();
    final stored = _StoredChallenge(
      challengeId: 'otp_${issuedAt.microsecondsSinceEpoch}',
      phoneE164: phoneE164,
      sessionId: sessionId,
      code: code,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(
        const Duration(seconds: EnvConfig.codeExpirySeconds),
      ),
      resendAvailableAt: issuedAt.add(
        const Duration(seconds: EnvConfig.resendCooldownSeconds),
      ),
      attemptsRemaining: EnvConfig.maxVerifyAttempts,
    );
    _challenges[stored.challengeId] = stored;
    return OtpChallenge(
      challengeId: stored.challengeId,
      phoneE164: phoneE164,
      sessionId: sessionId,
      issuedAt: issuedAt,
      expiresAt: stored.expiresAt,
      resendAvailableAt: stored.resendAvailableAt,
      attemptsRemaining: stored.attemptsRemaining,
      resendCount: _resendUsage[phoneE164] ?? 0,
      debugCode: kDebugMode ? code : null,
    );
  }

  void _enforceRequestLimit(String phoneE164) {
    final usage = _resendUsage[phoneE164] ?? 0;
    if (usage > EnvConfig.maxResends) {
      throw const OtpRateLimitedException(
        message: 'Too many codes requested for this number. Try again later.',
        retryAfter: Duration(minutes: 10),
      );
    }
  }

  String _generateCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  Future<void> _latency() =>
      Future<void>.delayed(const Duration(milliseconds: 350));
}

class _StoredChallenge {
  _StoredChallenge({
    required this.challengeId,
    required this.phoneE164,
    required this.sessionId,
    required this.code,
    required this.issuedAt,
    required this.expiresAt,
    required this.resendAvailableAt,
    required this.attemptsRemaining,
  });

  final String challengeId;
  final String phoneE164;
  final String sessionId;
  final String code;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final DateTime resendAvailableAt;
  int attemptsRemaining;

  bool isExpired(DateTime now) => now.isAfter(expiresAt);
}

/// Returned when there is no backend URL and preview mode is disabled.
///
/// It fails loudly instead of pretending a code was sent.
class UnconfiguredOtpVerificationService implements OtpVerificationService {
  const UnconfiguredOtpVerificationService();

  @override
  String get providerLabel => 'Not configured';

  @override
  bool get isConfigured => false;

  @override
  Future<OtpChallenge> requestCode({
    required String phoneE164,
    required String sessionId,
  }) async => throw const OtpNotConfiguredException();

  @override
  Future<OtpChallenge> resendCode({
    required String challengeId,
    required String sessionId,
  }) async => throw const OtpNotConfiguredException();

  @override
  Future<void> verify({
    required String challengeId,
    required String phoneE164,
    required String sessionId,
    required String code,
  }) async => throw const OtpNotConfiguredException();
}

/// Chooses the OTP implementation for the current build configuration.
OtpVerificationService resolveOtpService({http.Client? client}) {
  if (EnvConfig.backendConfigured) {
    return HttpOtpVerificationService(client: client);
  }
  if (EnvConfig.previewOtpEnabled) return PreviewOtpVerificationService();
  return const UnconfiguredOtpVerificationService();
}
