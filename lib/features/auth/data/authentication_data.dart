import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env_config.dart';
import '../../account/domain/account_models.dart';
import '../domain/account_repository.dart';
import '../domain/authentication_repository.dart';

// -----------------------------------------------------------------------------
// Production
// -----------------------------------------------------------------------------

/// Talks to the Haven Link backend; the server owns password hashing, session
/// tokens and role assignment.
class HttpAuthenticationRepository implements AuthenticationRepository {
  HttpAuthenticationRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  String? _accessToken;

  @override
  String get label => 'Haven Link accounts';

  @override
  bool get isConfigured => EnvConfig.backendConfigured;

  @override
  String? get accessToken => _accessToken;

  @override
  Future<User> signIn({required String email, required String password}) async {
    final body = await _post('/api/v1/auth/login', {
      'email': email,
      'password': password,
    });
    return _userFrom(body);
  }

  @override
  Future<User> register({
    required String fullName,
    required String email,
    required String phoneE164,
    required String password,
    required String challengeId,
    required String sessionId,
    required AccountRole role,
    Set<AgentCapability> capabilities = const {},
    Set<AgentWorkspace> workspaces = const {},
  }) async {
    final body = await _post('/api/v1/auth/register', {
      'fullName': fullName,
      'email': email,
      'phone': phoneE164,
      'password': password,
      'challengeId': challengeId,
      'sessionId': sessionId,
      'role': role.identifier,
      'capabilities': capabilities.map((item) => item.name).toList(),
      if (workspaces.isNotEmpty)
        'workspaces': workspaces.map((item) => item.identifier).toList(),
    });
    return _userFrom(body);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _client
          .post(
            EnvConfig.endpoint(path),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400) {
        final decoded = jsonDecode(response.body);
        final message =
            decoded is Map<String, dynamic> && decoded['message'] is String
            ? decoded['message'] as String
            : decoded is Map<String, dynamic> && decoded['error'] is String
            ? decoded['error'] as String
            : 'Authentication was rejected.';
        throw StateError(message);
      }
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (error) {
      if (error is StateError) rethrow;
      throw StateError(
        'We could not reach Haven Link accounts. Check your connection.',
      );
    }
  }

  User _userFrom(Map<String, dynamic> json) {
    final userJson = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : json;
    _accessToken = json['token'] as String? ?? _accessToken;
    return User(
      id: userJson['id'] as String,
      fullName: userJson['fullName'] as String? ?? '',
      email: userJson['email'] as String? ?? '',
      phone: userJson['phone'] as String? ?? '',
      role:
          AccountRole.fromIdentifier(userJson['role'] as String? ?? '') ??
          AccountRole.customer,
      verification:
          (((userJson['verification'] as String?) == 'verified') ||
              (userJson['phoneVerified'] as bool? ?? false))
          ? AccountVerification.verified
          : AccountVerification.unverified,
      accountEnabled: userJson['accountEnabled'] as bool? ?? true,
      capabilities: (userJson['capabilities'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map(
            (value) => AgentCapability.values
                .where((item) => item.name == value)
                .firstOrNull,
          )
          .whereType<AgentCapability>()
          .toSet(),
      workspaces: _workspacesFrom(userJson['workspaces']),
    );
  }

  /// Accepts `["HOTEL"]` or `[{"workspace":"HOTEL","status":"active"}]` and
  /// keeps only active workspaces.
  Set<AgentWorkspace> _workspacesFrom(Object? raw) {
    if (raw is! List) return const {};
    final result = <AgentWorkspace>{};
    for (final item in raw) {
      final String? name;
      if (item is String) {
        name = item;
      } else if (item is Map && (item['status'] ?? 'active') == 'active') {
        name = (item['workspace'] ?? item['type']) as String?;
      } else {
        name = null;
      }
      final parsed = name == null ? null : AgentWorkspace.fromIdentifier(name);
      if (parsed != null) result.add(parsed);
    }
    return result;
  }
}

/// Local sign-in used while no backend is configured.
///
/// It never checks a password and never talks to a server, so every account it
/// returns is flagged `isPreviewSession`. It is confined to debug builds and
/// the UI says so wherever it is used.
///
/// [register] is only ever reached from the registration screen *after*
/// `OtpVerificationService.verify` completed normally — the flow has no path
/// that creates a verified account without a successful verification.
class DevelopmentAuthenticationRepository implements AuthenticationRepository {
  DevelopmentAuthenticationRepository({required this._accounts}) {
    assert(
      kDebugMode,
      'DevelopmentAuthenticationRepository must never run outside debug builds.',
    );
  }

  final AccountRepository _accounts;

  @override
  String get label => 'Local development sign-in (no backend)';

  @override
  bool get isConfigured => kDebugMode;

  @override
  String? get accessToken => null;

  @override
  Future<User> signIn({required String email, required String password}) async {
    final account = await _accounts.findByEmail(email);
    if (account == null) {
      throw StateError('No account found for that email address.');
    }
    if (!account.accountEnabled) {
      throw StateError(
        'This account is suspended. Contact Haven Link support.',
      );
    }
    return account.copyWith(isPreviewSession: true);
  }

  @override
  Future<User> register({
    required String fullName,
    required String email,
    required String phoneE164,
    required String password,
    required String challengeId,
    required String sessionId,
    required AccountRole role,
    Set<AgentCapability> capabilities = const {},
    Set<AgentWorkspace> workspaces = const {},
  }) async {
    final account = User(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      fullName: fullName,
      email: email.trim(),
      phone: phoneE164,
      role: role,
      verification: AccountVerification.verified,
      capabilities: capabilities,
      workspaces: workspaces,
      isPreviewSession: true,
    );
    return _accounts.create(account);
  }
}

/// Picks the authentication implementation for this build.
AuthenticationRepository resolveAuthenticationRepository({
  required AccountRepository accounts,
  http.Client? client,
}) {
  if (EnvConfig.backendConfigured) {
    return HttpAuthenticationRepository(client: client);
  }
  if (kDebugMode) {
    return DevelopmentAuthenticationRepository(accounts: accounts);
  }
  return const UnconfiguredAuthenticationRepository();
}

class UnconfiguredAuthenticationRepository implements AuthenticationRepository {
  const UnconfiguredAuthenticationRepository();

  @override
  String get label => 'Backend not configured';

  @override
  bool get isConfigured => false;

  @override
  String? get accessToken => null;

  StateError _unavailable() => StateError(
    'Account registration and sign-in require a configured Haven Link backend.',
  );

  @override
  Future<User> signIn({
    required String email,
    required String password,
  }) async => throw _unavailable();

  @override
  Future<User> register({
    required String fullName,
    required String email,
    required String phoneE164,
    required String password,
    required String challengeId,
    required String sessionId,
    required AccountRole role,
    Set<AgentCapability> capabilities = const {},
    Set<AgentWorkspace> workspaces = const {},
  }) async => throw _unavailable();
}
