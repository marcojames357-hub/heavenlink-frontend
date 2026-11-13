import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haven_link/features/reviews/data/review_repository.dart';
import 'package:haven_link/features/reviews/domain/review_models.dart';
import 'package:haven_link/features/reviews/presentation/review_flow_screen.dart';
import 'package:haven_link/features/reviews/presentation/property_reviews_section.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

TripBooking _trip() => TripBooking.fromJson({
  'id': 'booking-1',
  'reference': 'ref-1',
  'checkIn': '2026-03-10T12:00:00.000Z',
  'checkOut': '2026-03-12T10:00:00.000Z',
  'nights': 2,
  'status': 'completed',
  'phase': 'completed',
  'canReview': true,
  'property': {
    'id': 'property-1',
    'name': 'Garden Lodge',
    'neighborhood': 'Njiro',
    'city': 'Arusha',
  },
});

Map<String, dynamic> _reviewJson() => {
  'id': 'r1',
  'overallRating': 5,
  'createdAt': '2026-03-13T10:00:00.000Z',
  'status': 'published',
};

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('guest rates nine categories and review is submitted', (
    tester,
  ) async {
    Map<String, dynamic>? body;
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path.endsWith('/reviews')) {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'review': _reviewJson()}), 201);
      }
      return http.Response('{}', 404);
    });
    final repository = ReviewRepository(
      tokenProvider: () => 't',
      client: client,
    );
    await _pump(
      tester,
      ReviewFlowScreen(repository: repository, trip: _trip()),
    );

    expect(find.text('Rate Your Stay'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.textContaining('rate all nine'), findsOneWidget);
    expect(body, isNull);

    for (final label in reviewCategoryLabels.values) {
      final star = find.byTooltip('$label: 4 stars');
      await tester.ensureVisible(star);
      await tester.tap(star);
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Thank you for reviewing your stay!'), findsNothing);
    await tester.ensureVisible(find.text('Submit review'));
    await tester.tap(find.text('Submit review'));
    await tester.pumpAndSettle();

    expect(body, isNotNull);
    expect(body, containsPair('bookingId', 'booking-1'));
    expect(body, containsPair('overallRating', 4));
    expect(find.text('Thank you for reviewing your stay!'), findsOneWidget);
  });

  testWidgets('no success message when the backend rejects the review', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => http.Response(jsonEncode({'error': 'Duplicate'}), 409),
    );
    final repository = ReviewRepository(
      tokenProvider: () => 't',
      client: client,
    );
    await _pump(
      tester,
      ReviewFlowScreen(repository: repository, trip: _trip()),
    );
    for (final label in reviewCategoryLabels.values) {
      final star = find.byTooltip('$label: 5 stars');
      await tester.ensureVisible(star);
      await tester.tap(star);
      await tester.pump();
    }
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit review'));
    await tester.tap(find.text('Submit review'));
    await tester.pumpAndSettle();

    expect(find.text('Thank you for reviewing your stay!'), findsNothing);
  });

  testWidgets('report-only mode validates before sending', (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 404);
    });
    final repository = ReviewRepository(
      tokenProvider: () => 't',
      client: client,
    );
    await _pump(
      tester,
      ReviewFlowScreen(repository: repository, trip: _trip(), reportOnly: true),
    );
    await tester.tap(find.text('Submit report'));
    await tester.pump();
    expect(calls, 0);
    expect(find.text('Your report has been received'), findsNothing);
  });

  testWidgets('empty property reviews show the verified-guest prompt', (
    tester,
  ) async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'summary': {'count': 0, 'average': null, 'categories': {}},
          'reviews': [],
          'pagination': {'page': 1, 'pages': 1, 'total': 0},
        }),
        200,
      ),
    );
    final repository = ReviewRepository(
      tokenProvider: () => null,
      client: client,
    );
    await _pump(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: PropertyReviewsSection(
            propertyId: 'property-1',
            tokenProvider: () => null,
            repository: repository,
          ),
        ),
      ),
    );
    expect(
      find.text(
        'No reviews yet. Be the first verified guest to share your experience.',
      ),
      findsOneWidget,
    );
  });
}
