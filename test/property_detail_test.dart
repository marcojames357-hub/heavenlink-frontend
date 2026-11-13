import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haven_link/core/state/haven_link_store.dart';
import 'package:haven_link/features/properties/domain/property.dart';
import 'package:haven_link/features/properties/presentation/property_detail_screen.dart';

Property _property({
  PropertyBusinessModel model = PropertyBusinessModel.contactUnlock,
  List<String> imageUrls = const [],
  List<AmenityDetail> amenityDetails = const [],
}) => Property(
  id: 'p1',
  name: 'Green Palm Apartment',
  city: 'Dar es Salaam',
  neighborhood: 'Sinza',
  priceTzs: 650000,
  businessModel: model,
  category: PropertyCategory.house,
  imageUrl: 'https://example.invalid/a.jpg',
  imageUrls: imageUrls,
  rating: 0,
  reviewCount: 0,
  bedrooms: 2,
  bathrooms: 1,
  amenities: const ['Water tank', 'Balcony'],
  amenityDetails: amenityDetails,
  description: 'Modern two-bedroom apartment',
  available: true,
  furnished: false,
  parking: true,
  water: true,
  electricity: true,
  security: true,
  propertyVerification: VerificationStatus.unverified,
  ownerVerification: VerificationStatus.unverified,
  managerName: 'Asha Mhando',
);

Future<void> _pump(WidgetTester tester, Property property) async {
  final store = HavenLinkStore();
  addTearDown(store.dispose);
  tester.view.physicalSize = const Size(1100, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: PropertyDetailScreen(property: property, store: store),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('detail body keeps its height and the action bar stays at the '
      'bottom', (tester) async {
    await _pump(tester, _property());

    final scroll = tester.getRect(find.byType(SingleChildScrollView).first);
    expect(scroll.height, greaterThan(400));
    final button = tester.getRect(find.byType(FilledButton));
    expect(button.left, greaterThan(650));
    expect(button.top, greaterThan(60));
    expect(button.bottom, lessThan(800));
    expect(find.text('Green Palm Apartment'), findsOneWidget);
    expect(find.text('Modern two-bedroom apartment'), findsOneWidget);
    expect(find.text('Water tank'), findsOneWidget);
    expect(find.text('No reviews yet'), findsNothing);
    expect(find.text('Guest reviews'), findsNothing);
  });

  testWidgets('gallery lists each distinct photo once', (tester) async {
    await _pump(
      tester,
      _property(
        imageUrls: const [
          'https://example.invalid/a.jpg',
          'https://example.invalid/b.jpg',
        ],
      ),
    );
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('amenity descriptions are shown on the customer detail page', (
    tester,
  ) async {
    await _pump(
      tester,
      _property(
        amenityDetails: const [
          AmenityDetail(
            name: 'Breakfast',
            description: 'Served daily from 6:30 to 10:00.',
          ),
        ],
      ),
    );
    expect(
      find.text('Breakfast: Served daily from 6:30 to 10:00.'),
      findsOneWidget,
    );
  });

  testWidgets('rentals expose nearby-service search and no booking button', (
    tester,
  ) async {
    await _pump(tester, _property());
    await tester.scrollUntilVisible(
      find.text('Find nearby services'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Hospitals'), findsOneWidget);
    expect(find.text('Book now'), findsNothing);
    expect(find.text('Unlock Contact & Messaging'), findsOneWidget);
  });

  testWidgets('stays show the booking action', (tester) async {
    await _pump(tester, _property(model: PropertyBusinessModel.bookable));
    expect(find.text('Book now'), findsOneWidget);
    expect(find.text('Stay information'), findsOneWidget);
    expect(find.text('No reviews yet'), findsWidgets);
  });
}
