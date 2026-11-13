import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haven_link/core/state/haven_link_store.dart';
import 'package:haven_link/features/home/presentation/home_sections.dart';
import 'package:haven_link/features/home/presentation/haven_link_shell.dart';
import 'package:haven_link/features/properties/data/property_repository.dart';
import 'package:haven_link/features/properties/domain/property.dart';
import 'package:haven_link/features/properties/presentation/property_detail_screen.dart';
import 'package:haven_link/features/properties/presentation/widgets/property_extras.dart';
import 'package:haven_link/features/properties/presentation/widgets/property_photo.dart';

const _rental = Property(
  id: 'fidelity-rental',
  name: 'Demo rental',
  city: 'Dar es Salaam',
  neighborhood: 'Masaki',
  priceTzs: 650000,
  businessModel: PropertyBusinessModel.contactUnlock,
  category: PropertyCategory.house,
  imageUrl: '',
  rating: 0,
  reviewCount: 0,
  bedrooms: 2,
  bathrooms: 1,
  amenities: [],
  description: 'A family rental.',
  available: true,
  furnished: false,
  parking: true,
  water: true,
  electricity: true,
  security: true,
  propertyVerification: VerificationStatus.unverified,
  ownerVerification: VerificationStatus.unverified,
  managerName: 'Demo agent',
);

void main() {
  for (final size in [
    const Size(320, 720),
    const Size(768, 1024),
    const Size(1280, 900),
    const Size(1920, 1080),
  ]) {
    testWidgets(
      'reference home geometry and anchor navigation fit width ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final store = HavenLinkStore(
          repository: MockPropertyRepository(properties: const [_rental]),
        );
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
        expect(tester.takeException(), isNull);
        final scroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('home-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        for (
          double offset = 500;
          offset < scroll.position.maxScrollExtent;
          offset += 500
        ) {
          scroll.position.jumpTo(offset);
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'home at offset $offset',
          );
        }
        if (size.width >= 1440) {
          await tester.tap(find.text('Discover'));
          await tester.pumpAndSettle();
          expect(
            find.text('Every kind of space, one trusted platform'),
            findsOneWidget,
          );
          expect(find.byKey(const Key('nav-stays')), findsOneWidget);
          expect(find.byKey(const Key('nav-rentals')), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('home date selection is passed to the existing search callback', (
    tester,
  ) async {
    DateTimeRange? submittedDates;
    String? submittedQuery;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeSearchPanel(
            onSearch: (_, _, _) {},
            onSearchWithDates: (_, query, _, dates) {
              submittedDates = dates;
              submittedQuery = query;
            },
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('home-search-location')),
      'Arusha',
    );
    await tester.tap(find.byKey(const Key('home-search-dates')));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    final today = DateUtils.dateOnly(DateTime.now());
    final dates = DateTimeRange(
      start: today.add(const Duration(days: 1)),
      end: today.add(const Duration(days: 3)),
    );
    tester.state<NavigatorState>(find.byType(Navigator).first).pop(dates);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-search-submit')));
    expect(submittedQuery, 'Arusha');
    expect(submittedDates, dates);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rental gallery uses a three-photo mosaic on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 760,
            child: PropertyGallery(
              mosaic: true,
              photos: [
                'https://example.invalid/a.jpg',
                'https://example.invalid/b.jpg',
                'https://example.invalid/c.jpg',
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PropertyPhoto), findsNWidgets(3));
    final photos = tester
        .widgetList<PropertyPhoto>(find.byType(PropertyPhoto))
        .toList();
    expect(photos.map((photo) => photo.imageUrl).toSet(), hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rental unlock summary reflects the actual configured fee', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = HavenLinkStore();
    addTearDown(store.dispose);
    store.feeSettings.updateUnlockFee(8000);
    await tester.pumpWidget(
      MaterialApp(
        home: PropertyDetailScreen(property: _rental, store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unlock fee'), findsOneWidget);
    expect(find.text('TZS 8,000'), findsOneWidget);
    expect(
      find.text('Information appears only after payment verification.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
