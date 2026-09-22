// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haven_link/app/haven_link_app.dart';
import 'package:haven_link/core/state/haven_link_store.dart';
import 'package:haven_link/core/config/business_config.dart';
import 'package:haven_link/core/formatters/currency_formatter.dart';
import 'package:haven_link/features/checkout/presentation/checkout_screen.dart';
import 'package:haven_link/features/properties/domain/property.dart';
import 'package:haven_link/features/properties/presentation/property_detail_screen.dart';
import 'package:haven_link/features/home/presentation/home_screen.dart';
import 'package:haven_link/features/search/presentation/property_browse_screen.dart';

void main() {
  testWidgets('Haven Link opens with its product promise', (tester) async {
    await tester.pumpWidget(const HavenLinkApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.text('Find Your Perfect Space with Confidence.'),
      findsOneWidget,
    );
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Find your kind of stay'), findsOneWidget);
  });

  testWidgets('Bookable and rental searches remain distinct', (tester) async {
    final store = HavenLinkStore();
    addTearDown(store.dispose);
    await store.loadProperties();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PropertyBrowseScreen(
            store: store,
            businessModel: PropertyBusinessModel.bookable,
            onOpenProperty: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Stays to book'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PropertyBrowseScreen(
            store: store,
            businessModel: PropertyBusinessModel.contactUnlock,
            onOpenProperty: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Homes to rent'), findsOneWidget);
  });

  testWidgets('customer can open a locked rental from the main navigation', (
    tester,
  ) async {
    await tester.pumpWidget(const HavenLinkApp());
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byIcon(Icons.key_outlined),
      ),
    );
    await tester.pumpAndSettle();
    final rentalCardTitle = find.text('Bright Mbezi Beach Home');
    await tester.ensureVisible(rentalCardTitle);
    await tester.pumpAndSettle();
    await tester.tap(rentalCardTitle);
    await tester.pumpAndSettle();

    final detailScreen = find.byType(PropertyDetailScreen);
    expect(detailScreen, findsOneWidget);
    final title = find.descendant(
      of: detailScreen,
      matching: find.text('Bright Mbezi Beach Home'),
    );
    expect(title, findsOneWidget);
    expect(tester.getTopLeft(title).dy, lessThan(500));
    expect(
      find.descendant(
        of: detailScreen,
        matching: find.text('Exact location & contact locked'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('rental details show locked access without leaking address', (
    tester,
  ) async {
    final store = HavenLinkStore();
    addTearDown(store.dispose);
    await store.loadProperties();
    final rental = store.propertyById('rent-01')!;

    await tester.pumpWidget(
      MaterialApp(
        home: PropertyDetailScreen(property: rental, store: store),
      ),
    );
    await tester.pump();
    final propertyTitle = find.text('Bright Mbezi Beach Home');
    expect(propertyTitle, findsOneWidget);
    expect(tester.getTopLeft(propertyTitle).dy, lessThan(500));
    expect(find.text('Exact location & contact locked'), findsOneWidget);
    expect(find.textContaining('Plot 18, Bahari Road'), findsNothing);
  });

  test('Tanzanian pricing config formats the booking fee clearly', () {
    const stayPrice = 800000;
    final bookingFee = (stayPrice * BusinessConfig.bookingFeeRate).round();

    expect(bookingFee, 16000);
    expect(formatTzs(stayPrice + bookingFee), contains('816,000'));
    expect(BusinessConfig.defaultUnlockFeeTzs, 5000);
  });

  test('rental contact stays locked until a recorded unlock', () async {
    final store = HavenLinkStore();
    addTearDown(store.dispose);
    await store.loadProperties();
    final rental = store.propertyById('rent-01')!;

    expect(await store.contactFor(rental.id), isNull);
    await store.recordUnlock(rental);
    expect((await store.contactFor(rental.id))?.contactName, 'Mariam Joseph');

    await store.recordUnlock(rental);
    expect(store.unlockedProperties, hasLength(1));
  });

  testWidgets('successful rental preview payment reveals contact', (
    tester,
  ) async {
    final store = HavenLinkStore();
    addTearDown(store.dispose);
    store.startPreviewSession();
    await store.loadProperties();
    final rental = store.propertyById('rent-01')!;

    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(property: rental, store: store),
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pay '));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Location and contact unlocked'), findsOneWidget);
    expect(find.textContaining('Plot 18, Bahari Road'), findsOneWidget);
    expect(store.unlockedProperties, hasLength(1));
  });
}
