import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haven_link/core/state/haven_link_store.dart';
import 'package:haven_link/core/theme/app_theme.dart';
import 'package:haven_link/features/account/domain/account_models.dart';
import 'package:haven_link/features/auth/domain/authentication_repository.dart';
import 'package:haven_link/features/auth/domain/otp_verification_service.dart';
import 'package:haven_link/features/auth/presentation/auth_screen.dart';
import 'package:haven_link/features/auth/presentation/phone_verification/otp_verification_screen.dart';

class _Otp implements OtpVerificationService {
  bool verified = false;
  int requests = 0;
  @override
  String get providerLabel => 'Test verification';
  @override
  bool get isConfigured => true;
  @override
  Future<OtpChallenge> requestCode({
    required String phoneE164,
    required String sessionId,
  }) async {
    requests++;
    final now = DateTime.now();
    return OtpChallenge(
      challengeId: 'test-challenge',
      phoneE164: phoneE164,
      sessionId: sessionId,
      issuedAt: now,
      expiresAt: now.add(const Duration(minutes: 5)),
      resendAvailableAt: now,
      attemptsRemaining: 5,
      resendCount: 0,
    );
  }

  @override
  Future<OtpChallenge> resendCode({
    required String challengeId,
    required String sessionId,
  }) => throw UnimplementedError();
  @override
  Future<void> verify({
    required String challengeId,
    required String phoneE164,
    required String sessionId,
    required String code,
  }) async {
    if (code != '123456') throw const OtpInvalidCodeException();
    verified = true;
  }
}

class _Registration implements AuthenticationRepository {
  _Registration(this.otp);
  final _Otp otp;
  Set<AgentWorkspace>? requestedWorkspaces;
  AccountRole? requestedRole;
  @override
  String get label => 'Test registration';
  @override
  String? get accessToken => null;
  @override
  bool get isConfigured => true;
  @override
  Future<User> signIn({required String email, required String password}) =>
      throw UnimplementedError();
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
    expect(
      otp.verified,
      isTrue,
      reason: 'Registration must remain gated by verified OTP.',
    );
    requestedWorkspaces = workspaces;
    requestedRole = role;
    return User(
      id: 'registered',
      fullName: fullName,
      email: email,
      phone: phoneE164,
      role: role,
      verification: AccountVerification.verified,
      workspaces: workspaces,
      capabilities: capabilities,
    );
  }
}

void main() {
  for (final (label, role, workspace) in [
    ('Customer', AccountRole.customer, null),
    ('Rental Agent', AccountRole.rentalAgent, AgentWorkspace.rental),
    ('Apartment Stays Agent', AccountRole.stayAgent, AgentWorkspace.apartment),
    ('Hotel, Lodge & Motel Agent', AccountRole.stayAgent, AgentWorkspace.hotel),
  ]) {
    testWidgets(
      '$label registration keeps its explicit workspace through phone verification',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final otp = _Otp();
        final registration = _Registration(otp);
        final store = HavenLinkStore(
          otpService: otp,
          authentication: registration,
        );
        addTearDown(store.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AuthScreen(store: store, initialRegister: true),
                    ),
                  ),
                  child: const Text('Register'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Register'));
        await tester.pumpAndSettle();
        expect(find.text('Join Haven Link'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('auth-full-name')),
          'Amina Mussa',
        );
        await tester.enterText(
          find.byKey(const Key('auth-email')),
          'amina@example.test',
        );
        await tester.enterText(
          find.byKey(const Key('auth-phone')),
          '+255754123456',
        );
        await tester.enterText(
          find.byKey(const Key('auth-password')),
          'Secure1234',
        );
        final picker = find.byKey(const Key('auth-registration-type'));
        await tester.ensureVisible(picker);
        await tester.pumpAndSettle();
        await tester.tap(picker);
        await tester.pumpAndSettle();
        expect(find.text('System Admin'), findsNothing);
        expect(find.text('Admin'), findsNothing);
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('auth-submit')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('auth-submit')));
        await tester.pumpAndSettle();
        expect(otp.requests, 1);
        expect(registration.requestedRole, isNull);
        expect(find.byType(OtpVerificationScreen), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, '123456');
        await tester.pumpAndSettle();
        expect(registration.requestedRole, role);
        expect(
          registration.requestedWorkspaces,
          workspace == null ? isEmpty : equals({workspace}),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final size in [
    const Size(320, 640),
    const Size(768, 1024),
    const Size(1024, 700),
    const Size(1440, 1000),
  ]) {
    testWidgets('Figma registration form fits ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = HavenLinkStore();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: HavenTheme.light,
          home: AuthScreen(store: store, initialRegister: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const Key('auth-registration-type')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
