import '../../account/domain/account_models.dart';

/// Credentials and account lifecycle.
///
/// Phone verification itself lives in `OtpVerificationService`; this contract
/// only completes registration once the caller has already proved ownership of
/// the number.
abstract interface class AuthenticationRepository {
  /// Describes the active implementation for the UI.
  String get label;

  String? get accessToken;

  /// True when a real backend is answering.
  bool get isConfigured;

  Future<User> signIn({required String email, required String password});

  /// Registers an account with an already-verified phone number.
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
  });
}
