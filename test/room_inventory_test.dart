import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haven_link/core/state/haven_link_store.dart';
import 'package:haven_link/features/access/domain/access_control.dart';
import 'package:haven_link/features/agent_portal/domain/agent_models.dart';
import 'package:haven_link/features/agent_portal/presentation/room_inventory_tab.dart';
import 'package:haven_link/features/agent_portal/state/agent_portal_store.dart';
import 'package:haven_link/features/properties/domain/property.dart';

Property _property(String id, String name) => Property(
  id: id,
  name: name,
  city: 'Arusha',
  neighborhood: 'Central',
  priceTzs: 10000,
  businessModel: PropertyBusinessModel.bookable,
  category: PropertyCategory.hotel,
  imageUrl: 'https://example.invalid/a.jpg',
  rating: 0,
  reviewCount: 0,
  bedrooms: 1,
  bathrooms: 1,
  amenities: const [],
  description: 'Hotel',
  available: true,
  furnished: false,
  parking: false,
  water: false,
  electricity: false,
  security: false,
  propertyVerification: VerificationStatus.unverified,
  ownerVerification: VerificationStatus.unverified,
  managerName: 'Manager',
);

class _InventoryStore extends AgentPortalStore {
  _InventoryStore(HavenLinkStore store)
    : super(portal: Portal.stayAgent, store: store);

  @override
  List<Property> get myListings => [
    _property('a', 'Hotel Alpha'),
    _property('b', 'Hotel Beta'),
  ];

  final Map<String, Completer<List<PhysicalRoom>>> pending = {};

  @override
  Future<List<PhysicalRoom>> loadPhysicalRooms(String listingId) =>
      pending.putIfAbsent(listingId, Completer.new).future;

  @override
  Future<List<RoomType>> loadRoomTypes(String listingId) async => [];
}

PhysicalRoom _room(String propertyId, String number) => PhysicalRoom(
  id: '$propertyId-$number',
  propertyId: propertyId,
  roomNumber: number,
  status: 'active',
);

void main() {
  testWidgets('switching properties ignores stale inventory responses', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = HavenLinkStore();
    final agent = _InventoryStore(store);
    addTearDown(agent.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RoomInventoryTab(agentStore: agent)),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Hotel Alpha'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Hotel Beta').last);
    await tester.pump();

    agent.pending['a']!.complete([_room('a', 'OLD')]);
    await tester.pump();
    expect(find.text('Room OLD'), findsNothing);
    final addCategory = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Add room category'),
    );
    expect(addCategory.onPressed, isNull);

    agent.pending['b']!.complete([_room('b', 'NEW')]);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Room NEW'),
      300,
      scrollable: find
          .descendant(
            of: find.byType(RoomInventoryTab),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Room NEW'), findsOneWidget);
    expect(find.text('Room OLD'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
