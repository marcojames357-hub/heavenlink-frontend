import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haven_link/core/widgets/portal_page_header.dart';
import 'package:haven_link/core/state/haven_link_store.dart';
import 'package:haven_link/features/access/domain/access_control.dart';
import 'package:haven_link/features/account/domain/account_models.dart';
import 'package:haven_link/features/agent_portal/presentation/accommodation_agent_dashboard_screen.dart';
import 'package:haven_link/features/agent_portal/state/agent_portal_store.dart';
import 'package:haven_link/features/auth/domain/authentication_repository.dart';

class _WorkspaceAuthentication implements AuthenticationRepository {
  _WorkspaceAuthentication(this.workspaces);

  final Set<AgentWorkspace> workspaces;

  @override
  String get label => 'Test authentication';

  @override
  String? get accessToken => null;

  @override
  bool get isConfigured => true;

  @override
  Future<User> signIn({
    required String email,
    required String password,
  }) async => User(
    id: 'stay-agent',
    fullName: 'Stay Agent',
    email: email,
    phone: '+255700000303',
    role: AccountRole.stayAgent,
    verification: AccountVerification.verified,
    workspaces: workspaces,
  );

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
  }) => throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester,
  Set<AgentWorkspace> workspaces,
  Portal portal,
) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = HavenLinkStore(
    authentication: _WorkspaceAuthentication(workspaces),
  );
  addTearDown(store.dispose);
  await store.signIn(email: 'agent@hl.test', password: 'Demo1234');
  final agent = AgentPortalStore(portal: portal, store: store);
  addTearDown(agent.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: portal == Portal.apartmentAgent
          ? ApartmentAgentDashboardScreen(store: store, agentStore: agent)
          : StayAgentDashboardScreen(store: store, agentStore: agent),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('apartment portal has calendar but no hotel room management', (
    tester,
  ) async {
    await _pump(tester, {AgentWorkspace.apartment}, Portal.apartmentAgent);

    expect(find.text('Apartment Stays Portal'), findsOneWidget);
    expect(find.text('Add Apartment'), findsOneWidget);
    expect(find.text('My Apartments'), findsOneWidget);
    expect(find.text('Availability Calendar'), findsOneWidget);
    expect(find.byType(PortalPageHeader), findsOneWidget);
    expect(find.text('Room Categories'), findsNothing);
    expect(find.text('Physical Rooms'), findsNothing);
    expect(find.text('Reservations / Front Desk'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Alerts'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('portal-sidebar')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Alerts'), findsOneWidget);
  });

  testWidgets('hotel portal has room management but no apartment calendar', (
    tester,
  ) async {
    await _pump(tester, {AgentWorkspace.hotel}, Portal.stayAgent);

    expect(find.text('Hotel, Lodge & Motel Portal'), findsOneWidget);
    expect(find.text('My Properties'), findsOneWidget);
    expect(find.text('Add Hotel'), findsOneWidget);
    expect(find.text('Room Categories'), findsOneWidget);
    expect(find.text('Physical Rooms'), findsOneWidget);
    expect(find.text('Availability Calendar'), findsOneWidget);
    expect(find.text('Reservations / Front Desk'), findsOneWidget);
    expect(find.text('My Apartments'), findsNothing);
    expect(find.byType(PortalPageHeader), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Utilities & Expenses'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('portal-sidebar')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Utilities & Expenses'), findsOneWidget);
  });

  testWidgets('portals lay out without overflow on a phone-sized screen', (
    tester,
  ) async {
    for (final (portal, workspace) in [
      (Portal.apartmentAgent, AgentWorkspace.apartment),
      (Portal.stayAgent, AgentWorkspace.hotel),
    ]) {
      await _pump(tester, {workspace}, portal);
      tester.view.physicalSize = const Size(390, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$portal at 390px');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('hotel sidebar returns to the marketplace', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = HavenLinkStore(
      authentication: _WorkspaceAuthentication({AgentWorkspace.hotel}),
    );
    addTearDown(store.dispose);
    await store.signIn(email: 'agent@hl.test', password: 'Demo1234');
    final agent = AgentPortalStore(portal: Portal.stayAgent, store: store);
    addTearDown(agent.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      StayAgentDashboardScreen(store: store, agentStore: agent),
                ),
              ),
              child: const Text('Open workspace'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open workspace'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Back to marketplace'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('portal-sidebar')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Back to marketplace'));
    await tester.pumpAndSettle();
    expect(find.text('Open workspace'), findsOneWidget);
    expect(store.currentUser, isNotNull);
  });

  testWidgets('hotel-only agent is blocked from the apartment portal', (
    tester,
  ) async {
    await _pump(tester, {AgentWorkspace.hotel}, Portal.apartmentAgent);

    expect(find.text('Access Restricted'), findsOneWidget);
    expect(find.text('My Apartments'), findsNothing);
  });
}
