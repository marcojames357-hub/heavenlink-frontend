import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haven_link/core/state/haven_link_store.dart';
import 'package:haven_link/features/home/presentation/home_screen.dart';
import 'package:haven_link/features/home/presentation/haven_link_shell.dart';
import 'package:haven_link/features/auth/presentation/auth_screen.dart';
import 'package:haven_link/features/properties/data/property_repository.dart';
import 'package:haven_link/features/properties/domain/property.dart';
import 'package:haven_link/features/properties/presentation/property_detail_screen.dart';

const _sizes = <String, Size>{
  'small phone': Size(320, 640),
  'phone': Size(390, 844),
  'tablet': Size(768, 1024),
  'laptop': Size(1280, 800),
  'wide desktop': Size(1920, 1080),
};

Property _property(PropertyBusinessModel model) => Property(
  id: 'p-${model.name}',
  name: 'Green Palm Apartment with a rather long listing title',
  city: 'Dar es Salaam',
  neighborhood: 'Sinza',
  priceTzs: 650000,
  businessModel: model,
  category: PropertyCategory.house,
  imageUrl: 'https://example.invalid/a.jpg',
  imageUrls: const ['https://example.invalid/b.jpg'],
  rating: 0,
  reviewCount: 0,
  bedrooms: 2,
  bathrooms: 1,
  amenities: const ['Water tank', 'Balcony', 'Wifi', 'Garden', 'Generator'],
  description: 'Modern two-bedroom apartment close to shops and transport.',
  available: true,
  furnished: true,
  parking: true,
  water: true,
  electricity: true,
  security: true,
  propertyVerification: VerificationStatus.unverified,
  ownerVerification: VerificationStatus.unverified,
  managerName: 'Asha Mhando',
);

void _useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('wide auth uses the split-screen presentation', (tester) async {
    _useSize(tester, const Size(1280, 900));
    final store = HavenLinkStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(MaterialApp(home: AuthScreen(store: store)));
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.text('Every property journey. One trusted identity.'),
      findsOneWidget,
    );
    expect(find.text('Welcome back'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop create account opens registration and can go back', (
    tester,
  ) async {
    _useSize(tester, const Size(1280, 900));
    final store = HavenLinkStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: HavenLinkShell(
          store: store,
          locale: const Locale('en'),
          onLocaleChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Join Haven Link'), findsOneWidget);
    expect(find.text('PHONE NUMBER'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(HavenLinkShell), findsOneWidget);
    expect(find.byType(AuthScreen), findsNothing);
  });

  testWidgets('featured home property opens the live listing', (tester) async {
    final featured = _property(PropertyBusinessModel.bookable);
    final store = HavenLinkStore(
      repository: MockPropertyRepository(properties: [featured]),
    );
    addTearDown(store.dispose);
    Property? opened;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            store: store,
            onBrowse: (_) {},
            onOpenProperty: (property) => opened = property,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final featuredCard = find.byKey(const Key('featured-property-card'));
    expect(
      find.descendant(of: featuredCard, matching: find.text(featured.name)),
      findsOneWidget,
    );
    await tester.ensureVisible(featuredCard);
    await tester.pumpAndSettle();
    await tester.tap(featuredCard);
    await tester.pump();
    expect(opened, same(featured));
    expect(tester.takeException(), isNull);
  });

  for (final entry in _sizes.entries) {
    for (final model in PropertyBusinessModel.values) {
      testWidgets('${model.name} details fit a ${entry.key}', (tester) async {
        _useSize(tester, entry.value);
        final store = HavenLinkStore();
        addTearDown(store.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: PropertyDetailScreen(
              property: _property(model),
              store: store,
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));

        expect(tester.takeException(), isNull);
        final button = tester.getRect(find.byType(FilledButton));
        expect(button.right, lessThanOrEqualTo(entry.value.width));
        expect(button.bottom, lessThanOrEqualTo(entry.value.height));
      });
    }

    testWidgets('home shell fits a ${entry.key}', (tester) async {
      _useSize(tester, entry.value);
      final store = HavenLinkStore();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: HavenLinkShell(
            store: store,
            locale: const Locale('en'),
            onLocaleChanged: (_) {},
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);

      if (entry.value.width >= 900) {
        for (final key in ['nav-stays', 'nav-rentals']) {
          await tester.tap(find.byKey(Key(key)));
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull, reason: key);
        }
        await tester.tap(find.text('Log in'));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull, reason: 'account');
      } else {
        for (final icon in [
          HavenIcons.hotelOutlined,
          HavenIcons.keyOutlined,
          HavenIcons.personOutline,
        ]) {
          await tester.tap(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.byIcon(icon),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull, reason: '$icon');
        }
      }
    });
  }
}
