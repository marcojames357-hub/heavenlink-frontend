import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:haven_link/core/theme/app_theme.dart';
import 'package:haven_link/core/state/haven_link_store.dart';
import 'package:haven_link/features/access/domain/access_control.dart';
import 'package:haven_link/features/agent_portal/domain/agent_models.dart';
import 'package:haven_link/features/agent_portal/presentation/walk_in_dialog.dart';
import 'package:haven_link/features/agent_portal/state/agent_portal_store.dart';

class _WalkInStore extends AgentPortalStore {
  _WalkInStore(HavenLinkStore store)
    : super(portal: Portal.stayAgent, store: store);

  @override
  Future<List<WalkInReservation>> loadWalkIns(String listingId) async => [
    WalkInReservation(
      id: 'walk-in-1',
      roomId: 'room-1',
      guestName: 'Amina Guest',
      checkIn: DateTime(2026, 11, 11, 14),
      checkOut: DateTime(2026, 11, 12, 10),
      status: 'checkedIn',
      paymentStatus: 'partiallyPaid',
      priceTzs: 85000,
    ),
  ];
}

void main() {
  testWidgets('walk-in reservations render without overflow on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = HavenLinkStore();
    final agentStore = _WalkInStore(store);
    addTearDown(agentStore.dispose);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      ShadTheme(
        data: HavenTheme.shadcn,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => WalkInDialog(
                    store: agentStore,
                    propertyId: 'property-1',
                    rooms: const [
                      PhysicalRoom(
                        id: 'room-1',
                        propertyId: 'property-1',
                        roomNumber: '101',
                        status: 'active',
                        roomTypeId: 'category-1',
                        roomTypeName: 'Standard',
                      ),
                    ],
                  ),
                ),
                child: const Text('Open walk-ins'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open walk-ins'));
    await tester.pumpAndSettle();

    expect(find.text('Amina Guest'), findsOneWidget);
    expect(find.text('Room 101 · TZS 85,000'), findsOneWidget);
    expect(find.text('Partially paid'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Record walk-in'));
    await tester.pumpAndSettle();
    expect(find.text('Guest name'), findsOneWidget);
    expect(find.text('Expected checkout'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
