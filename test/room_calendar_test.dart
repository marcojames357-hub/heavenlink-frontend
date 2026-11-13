import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haven_link/core/state/haven_link_store.dart';
import 'package:haven_link/features/access/domain/access_control.dart';
import 'package:haven_link/features/agent_portal/domain/agent_models.dart';
import 'package:haven_link/features/agent_portal/domain/agent_repository.dart';
import 'package:haven_link/features/agent_portal/presentation/room_calendar_dialog.dart';
import 'package:haven_link/features/agent_portal/state/agent_portal_store.dart';

class CalendarRepository extends LocalAgentRepository {
  @override
  Future<List<RoomCalendarEntry>> loadRoomCalendar(
    String listingId,
    DateTime start,
    DateTime end,
  ) async => [
    RoomCalendarEntry(
      roomNumber: 'VIP-B',
      category: 'Deluxe',
      status: 'active',
      occupancy: 'vacant',
      events: [
        RoomCalendarEvent(
          kind: 'online',
          start: start,
          end: end,
          guestName: 'Guest',
        ),
        RoomCalendarEvent(
          kind: 'walkIn',
          start: start,
          end: end,
          guestName: 'Walk-in',
        ),
        RoomCalendarEvent(kind: 'hold', start: start, end: end),
        RoomCalendarEvent(
          kind: 'blocked',
          start: start,
          end: end,
          reason: 'Repair',
        ),
      ],
    ),
  ];
}

void main() {
  test('date-only maintenance blocks retain their UTC calendar day', () {
    final block = RoomCalendarEvent.fromJson({
      'kind': 'blocked',
      'start': '2026-11-09',
      'end': '2026-11-10',
    });
    expect(block.start.isUtc, isTrue);
    expect(block.start.toIso8601String(), '2026-11-09T00:00:00.000Z');
  });

  testWidgets('calendar distinguishes reservation sources from occupancy', (
    tester,
  ) async {
    final store = HavenLinkStore();
    final agent = AgentPortalStore(
      portal: Portal.stayAgent,
      store: store,
      repository: CalendarRepository(),
    );
    addTearDown(agent.dispose);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomCalendarDialog(store: agent, propertyId: 'property'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No walk-in checked in'), findsOneWidget);
    await tester.tap(find.text('Room VIP-B · Deluxe'));
    await tester.pumpAndSettle();
    expect(find.text('Online reserved'), findsOneWidget);
    expect(find.text('Walk-in reserved / occupied'), findsOneWidget);
    expect(find.text('Temporarily held'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
  });
}
