import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:haven_link/core/state/haven_link_store.dart';
import 'package:haven_link/features/access/domain/access_control.dart';
import 'package:haven_link/features/agent_portal/presentation/listing_editor_dialog.dart';
import 'package:haven_link/features/agent_portal/presentation/pin_map.dart';
import 'package:haven_link/features/agent_portal/state/agent_portal_store.dart';
import 'package:haven_link/features/properties/data/property_repository.dart';
import 'package:haven_link/features/properties/domain/property.dart';

class _LocationPlatform extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestedPermission = LocationPermission.whileInUse;
  int requests = 0;
  Object? error;
  Future<Position>? pendingPosition;
  Position position = _position(-6.812345, 39.234567);

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return requestedPermission;
  }

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    if (error != null) return Future.error(error!);
    return pendingPosition ?? Future.value(position);
  }
}

Position _position(double latitude, double longitude) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime(2026),
  accuracy: 12.2,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _Repository implements PropertyRepository {
  Property? saved;
  List<String> uploadedUrls = const [];
  int uploadCalls = 0;

  @override
  Future<List<String>> uploadPhotos(
    List<({String name, List<int> bytes})> files,
  ) async {
    uploadCalls++;
    return uploadedUrls;
  }

  @override
  Future<List<Property>> getProperties() async => [];

  @override
  Future<Property> save(
    Property property, {
    bool confirmInventoryModelChange = false,
    bool saveAsDraft = false,
  }) async {
    saved = property;
    return property;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Property _existing(PropertyBusinessModel model) => Property(
  id: 'existing',
  name: 'Existing property',
  city: 'Dar es Salaam',
  neighborhood: 'Sinza',
  priceTzs: 10000,
  businessModel: model,
  category: model == PropertyBusinessModel.bookable
      ? PropertyCategory.hotel
      : PropertyCategory.house,
  imageUrl: 'https://example.com/image.jpg',
  rating: 0,
  reviewCount: 0,
  bedrooms: 1,
  bathrooms: 1,
  amenities: const [],
  description: 'A suitable property.',
  available: true,
  furnished: false,
  parking: false,
  water: false,
  electricity: false,
  security: false,
  propertyVerification: VerificationStatus.unverified,
  ownerVerification: VerificationStatus.unverified,
  managerName: 'Manager',
  latitude: -6.7,
  longitude: 39.1,
);

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _open(
  WidgetTester tester,
  HavenLinkStore store,
  PropertyBusinessModel model, {
  Property? initial,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showListingEditorDialog(
              context: context,
              store: store,
              businessModel: model,
              initial: initial,
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String label, String value) async {
  final finder = _field(label);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.enterText(finder, value);
}

Future<void> _capture(WidgetTester tester) async {
  final button = find.text('Use current location');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
}

Future<void> _fillNewListing(
  WidgetTester tester,
  PropertyBusinessModel model,
) async {
  await _enter(tester, 'Listing title', 'Example property');
  await _enter(tester, 'City', 'Dar es Salaam');
  await _enter(tester, 'Area / neighbourhood', 'Sinza');
  await _enter(tester, 'Description', 'A suitable property.');
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  await _enter(
    tester,
    'Amenity descriptions',
    'Breakfast | Available daily from 6:30 to 10:00.\nParking | Free overnight parking.',
  );
  if (model == PropertyBusinessModel.bookable) {
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }
  await _enter(
    tester,
    model == PropertyBusinessModel.bookable
        ? 'Price per night (TZS)'
        : 'Rent (TZS)',
    '10000',
  );
  await _enter(tester, 'Cover photograph URL', 'https://example.com/image.jpg');
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

Future<void> _moveToReview(WidgetTester tester) async {
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

void main() {
  late GeolocatorPlatform previous;
  late _LocationPlatform location;
  late _Repository repository;
  late HavenLinkStore store;

  setUp(() {
    previous = GeolocatorPlatform.instance;
    location = _LocationPlatform();
    GeolocatorPlatform.instance = location;
    repository = _Repository();
    store = HavenLinkStore(repository: repository);
  });

  tearDown(() {
    GeolocatorPlatform.instance = previous;
    store.dispose();
  });

  for (final model in PropertyBusinessModel.values) {
    testWidgets('captures and saves a new ${model.name} location', (
      tester,
    ) async {
      await _open(tester, store, model);
      expect(
        find.textContaining('You must be at the property you are adding'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(_field('Latitude')).readOnly, isTrue);
      expect(tester.widget<TextField>(_field('Longitude')).readOnly, isTrue);
      expect(
        tester.widget<TextField>(_field('Latitude')).controller!.text,
        '-6.812345',
      );
      expect(
        tester.widget<TextField>(_field('Longitude')).controller!.text,
        '39.234567',
      );
      expect(find.textContaining('approximately 13 m'), findsOneWidget);
      expect(find.byTooltip('Move pin north'), findsNothing);
      await _fillNewListing(tester, model);
      await tester.tap(find.text('Save listing'));
      await tester.pumpAndSettle();
      expect(repository.saved?.latitude, -6.812345);
      expect(repository.saved?.longitude, 39.234567);
      expect(repository.saved?.businessModel, model);
      expect(
        repository.saved?.amenityDetails.map((item) => item.name),
        contains('Breakfast'),
      );
      expect(
        repository.saved?.amenityDetails.first.description,
        'Available daily from 6:30 to 10:00.',
      );
    });
  }

  testWidgets('denied permission blocks a new listing until retry succeeds', (
    tester,
  ) async {
    location.permission = LocationPermission.denied;
    location.requestedPermission = LocationPermission.denied;
    await _open(tester, store, PropertyBusinessModel.bookable);
    expect(location.requests, 1);
    expect(
      find.textContaining('Location permission is denied'),
      findsOneWidget,
    );
    await _enter(tester, 'Listing title', 'Example property');
    await _enter(tester, 'City', 'Dar es Salaam');
    await _enter(tester, 'Area / neighbourhood', 'Sinza');
    await _enter(tester, 'Description', 'A suitable property.');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Capture your current location'), findsWidgets);
    expect(repository.saved, isNull);
    location.requestedPermission = LocationPermission.whileInUse;
    await _capture(tester);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_field('Latitude')).controller!.text,
      '-6.812345',
    );
    expect(
      tester.widget<TextField>(_field('Longitude')).controller!.text,
      '39.234567',
    );
  });

  testWidgets('existing coordinates stay unchanged until recaptured', (
    tester,
  ) async {
    final initial = _existing(PropertyBusinessModel.contactUnlock);
    await _open(tester, store, initial.businessModel, initial: initial);
    expect(
      tester.widget<TextField>(_field('Latitude')).controller!.text,
      '-6.7',
    );
    await _moveToReview(tester);
    await tester.tap(find.text('Save listing'));
    await tester.pumpAndSettle();
    expect(repository.saved?.latitude, -6.7);
    expect(repository.saved?.longitude, 39.1);
    await _open(tester, store, initial.businessModel, initial: initial);
    await _capture(tester);
    await tester.pumpAndSettle();
    await _moveToReview(tester);
    await tester.tap(find.text('Save listing'));
    await tester.pumpAndSettle();
    expect(repository.saved?.latitude, -6.812345);
    expect(repository.saved?.longitude, 39.234567);
  });

  testWidgets('disabled location service gives a retryable error', (
    tester,
  ) async {
    location.enabled = false;
    await _open(tester, store, PropertyBusinessModel.contactUnlock);
    expect(
      find.textContaining('Turn on device location services'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(_field('Latitude')).controller!.text,
      isEmpty,
    );
    location.enabled = true;
    await _capture(tester);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Turn on device location services'),
      findsNothing,
    );
  });

  testWidgets('shows location errors and permits retry', (tester) async {
    location.error = const PermissionDeniedException('Permission denied');
    await _open(tester, store, PropertyBusinessModel.bookable);
    expect(
      find.textContaining('Location permission is denied'),
      findsOneWidget,
    );
    location.error = TimeoutException('Timed out');
    await _capture(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Location request timed out'), findsOneWidget);
    location.error = null;
    await _capture(tester);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_field('Longitude')).controller!.text,
      '39.234567',
    );
  });

  testWidgets('rejects invalid coordinates and preserves the previous pin', (
    tester,
  ) async {
    final initial = _existing(PropertyBusinessModel.bookable);
    location.position = _position(91, 39);
    await _open(tester, store, initial.businessModel, initial: initial);
    await _capture(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('invalid location'), findsOneWidget);
    expect(
      tester.widget<TextField>(_field('Latitude')).controller!.text,
      '-6.7',
    );
    expect(
      tester.widget<TextField>(_field('Longitude')).controller!.text,
      '39.1',
    );
  });

  testWidgets('saving is disabled while location is being acquired', (
    tester,
  ) async {
    final pending = Completer<Position>();
    location.pendingPosition = pending.future;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showListingEditorDialog(
                context: context,
                store: store,
                businessModel: PropertyBusinessModel.bookable,
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    pending.complete(_position(-6.8, 39.2));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'apartment location step has country, region and an editable pin',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showListingEditorDialog(
                  context: context,
                  store: store,
                  businessModel: PropertyBusinessModel.bookable,
                  categories: const [PropertyCategory.shortStayApartment],
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await _enter(tester, 'Listing title', 'Sea view apartment');
      await _enter(tester, 'Description', 'A bright furnished apartment.');
      await _enter(tester, 'Maximum guests', '4');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(_field('Country'), findsOneWidget);
      expect(_field('Region / state'), findsOneWidget);
      expect(tester.widget<TextField>(_field('Latitude')).readOnly, isFalse);
      expect(find.text('Check pin on map'), findsOneWidget);
      expect(
        tester.widget<TextField>(_field('Country')).controller!.text,
        'Tanzania',
      );
    },
  );

  testWidgets('listing editor fits a phone-sized screen', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final model in PropertyBusinessModel.values) {
      await _open(tester, store, model);
      await _enter(tester, 'Listing title', 'Example property');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '${model.name} editor');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('new hotel creates categories and named rooms in the wizard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final agent = AgentPortalStore(portal: Portal.stayAgent, store: store);
    addTearDown(agent.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showListingEditorDialog(
                context: context,
                store: store,
                businessModel: PropertyBusinessModel.bookable,
                categories: const [PropertyCategory.hotel],
                agentStore: agent,
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await _enter(tester, 'Listing title', 'Coast Hotel');
    await _enter(tester, 'City', 'Dar es Salaam');
    await _enter(tester, 'Area / neighbourhood', 'Sinza');
    await _enter(tester, 'Description', 'A suitable hotel.');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Add at least one room category to continue.'), findsOne);

    await tester.tap(find.text('Add room category'));
    await tester.pumpAndSettle();
    await _enter(tester, 'Category name', 'Deluxe');
    await _enter(tester, 'Price per night (TZS)', '90000');
    await _enter(tester, 'Planned category rooms', '2');
    await tester.tap(find.text('Save category'));
    await tester.pumpAndSettle();
    expect(find.text('Deluxe'), findsOneWidget);

    await tester.tap(find.byTooltip('Room identifiers'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('Room identifiers'), 'D01\nD02');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 of 2 rooms named'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await _enter(tester, 'Price per night (TZS)', '90000');
    await _enter(
      tester,
      'Cover photograph URL',
      'https://example.com/image.jpg',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Deluxe: 90000 TZS / night'), findsOneWidget);
    await tester.tap(find.text('Save listing'));
    await tester.pumpAndSettle();

    final id = repository.saved!.id;
    final types = await agent.loadRoomTypes(id);
    expect(types.map((type) => type.name), ['Deluxe']);
    expect(types.single.listingId, id);
    final rooms = await agent.loadPhysicalRooms(id);
    expect(rooms.map((room) => room.roomNumber).toSet(), {'D01', 'D02'});
    expect(rooms.every((room) => room.roomTypeId == types.single.id), isTrue);
  });

  testWidgets('apartment pin map toggles inline and moves the pin on tap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showListingEditorDialog(
                context: context,
                store: store,
                businessModel: PropertyBusinessModel.bookable,
                categories: const [PropertyCategory.shortStayApartment],
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await _enter(tester, 'Listing title', 'Sea view apartment');
    await _enter(tester, 'Description', 'A bright furnished apartment.');
    await _enter(tester, 'Maximum guests', '4');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await _enter(tester, 'Latitude', '-6.8');
    await _enter(tester, 'Longitude', '39.2');
    final toggle = find.text('Check pin on map');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(find.byType(PinMap), findsOneWidget);
    tester.widget<PinMap>(find.byType(PinMap)).onMoved(-6.9, 39.3);
    await tester.pump();
    expect(
      tester.widget<TextField>(_field('Latitude')).controller!.text,
      '-6.900000',
    );
    await tester.tap(find.text('Hide map'));
    await tester.pump();
    expect(find.byType(PinMap), findsNothing);
  });

  testWidgets('apartment photo upload fills the cover photo', (tester) async {
    repository.uploadedUrls = ['https://cdn.example.com/a.png'];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showListingEditorDialog(
                context: context,
                store: store,
                businessModel: PropertyBusinessModel.bookable,
                categories: const [PropertyCategory.shortStayApartment],
                picker: ({required bool pdf}) async => [
                  (name: 'a.png', bytes: [1, 2, 3]),
                ],
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await _enter(tester, 'Listing title', 'Sea view apartment');
    await _enter(tester, 'Description', 'A bright furnished apartment.');
    await _enter(tester, 'Maximum guests', '4');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await _enter(tester, 'Latitude', '-6.8');
    await _enter(tester, 'Longitude', '39.2');
    await _enter(tester, 'Region / state', 'Dar es Salaam');
    await _enter(tester, 'City', 'Dar es Salaam');
    await _enter(tester, 'Area / neighbourhood', 'Masaki');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    final upload = find.text('Upload photos from device');
    await tester.ensureVisible(upload);
    await tester.tap(upload);
    await tester.pumpAndSettle();
    expect(repository.uploadCalls, 1);
    expect(find.text('https://cdn.example.com/a.png'), findsWidgets);
  });
}
