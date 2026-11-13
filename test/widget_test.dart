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
import 'package:haven_link/core/widgets/portal_page_header.dart';
import 'package:haven_link/features/account/domain/account_models.dart';
import 'package:haven_link/features/account/presentation/account_screen.dart';
import 'package:haven_link/features/access/domain/access_control.dart';
import 'package:haven_link/features/auth/domain/authentication_repository.dart';
import 'package:haven_link/features/home/presentation/haven_link_shell.dart';
import 'package:haven_link/features/checkout/presentation/checkout_screen.dart';
import 'package:haven_link/features/auth/presentation/auth_screen.dart';
import 'package:haven_link/features/properties/domain/property.dart';
import 'package:haven_link/features/properties/data/property_repository.dart';
import 'package:haven_link/features/properties/presentation/property_detail_screen.dart';
import 'package:haven_link/features/properties/presentation/widgets/property_map.dart';
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
    expect(find.text('Search properties'), findsOneWidget);
  });

  testWidgets('home language menu switches to Kiswahili', (tester) async {
    await tester.pumpWidget(const HavenLinkApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('Change language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kiswahili'));
    await tester.pumpAndSettle();

    expect(find.text('Mtandao wa makazi Tanzania'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Gundua'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('password visibility toggles in sign-in and registration', (
    tester,
  ) async {
    final store = HavenLinkStore();
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(home: AuthScreen(store: store)));
    await tester.pump();

    final signInPassword = find.descendant(
      of: find.byKey(const Key('auth-password')),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(signInPassword).obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(signInPassword).obscureText, isFalse);
    expect(find.byTooltip('Hide password'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();

    final createAccountLink = find.byKey(const Key('auth-mode-register'));
    await tester.ensureVisible(createAccountLink);
    await tester.pumpAndSettle();
    await tester.tap(createAccountLink);
    await tester.pump();
    final registrationPassword = find.descendant(
      of: find.byKey(const Key('auth-password')),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(registrationPassword).obscureText, isTrue);
    final registrationToggle = find.byTooltip('Show password');
    await tester.ensureVisible(registrationToggle);
    await tester.pumpAndSettle();
    await tester.tap(registrationToggle);
    await tester.pump();
    expect(tester.widget<TextField>(registrationPassword).obscureText, isFalse);
  });

  testWidgets('agent account navigation opens portal on a short screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(724, 340);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = HavenLinkStore();
    addTearDown(store.dispose);
    store.setCurrentUser(
      const User(
        id: 'review-agent',
        fullName: 'Review Agent',
        email: 'rental@hl.test',
        phone: '+255700000202',
        role: AccountRole.rentalAgent,
        verification: AccountVerification.verified,
      ),
    );

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
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    expect(find.text('Bookings'), findsNothing);
    expect(find.text('Unlocked properties'), findsNothing);
    expect(find.text('Recently viewed'), findsNothing);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Rental Agent Portal'), findsOneWidget);
    expect(find.text('My Listings'), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rental agent sign-in opens the rental portal', (tester) async {
    await _expectPortalOpensAfterSignIn(
      tester,
      AccountRole.rentalAgent,
      wide: true,
    );
  });

  testWidgets('stay agent sign-in opens the stay portal', (tester) async {
    await _expectPortalOpensAfterSignIn(tester, AccountRole.stayAgent);
  });

  testWidgets('admin sign-in opens the admin dashboard', (tester) async {
    await _expectPortalOpensAfterSignIn(tester, AccountRole.admin, wide: true);
  });

  testWidgets('stay and admin account screens show only their own portal', (
    tester,
  ) async {
    for (final entry in [
      (AccountRole.stayAgent, Portal.stayAgent, 'Stay Agent Portal'),
      (AccountRole.admin, Portal.admin, 'Admin Dashboard'),
    ]) {
      final store = HavenLinkStore();
      store.setCurrentUser(
        User(
          id: 'test-${entry.$1.identifier}',
          fullName: 'Review Account',
          email: 'review@test.invalid',
          phone: '+255700000205',
          role: entry.$1,
          verification: AccountVerification.verified,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountScreen(store: store, onOpenProperty: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(entry.$3), findsNothing);
      expect(find.text('Bookings'), findsNothing);
      expect(find.text('My bookings'), findsNothing);
      expect(find.text('Messages'), findsNothing);
      expect(find.text('Rental Agent Portal'), findsNothing);
      expect(find.text('Stay Agent Portal'), findsNothing);
      expect(find.text('Admin Dashboard'), findsNothing);
      store.dispose();
    }
  });

  testWidgets('customer account omits notifications and settings links', (
    tester,
  ) async {
    final store = HavenLinkStore();
    addTearDown(store.dispose);
    store.setCurrentUser(
      const User(
        id: 'test-customer',
        fullName: 'Review Customer',
        email: 'user@hl.test',
        phone: '+255700000206',
        role: AccountRole.customer,
        verification: AccountVerification.verified,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountScreen(store: store, onOpenProperty: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.byType(PortalPageHeader), findsOneWidget);
    expect(find.text('Help & support'), findsOneWidget);
  });

  testWidgets(
    'desktop customer workspace navigates and returns to marketplace',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = HavenLinkStore();
      addTearDown(store.dispose);
      store.setCurrentUser(
        const User(
          id: 'test-customer',
          fullName: 'Review Customer',
          email: 'user@hl.test',
          phone: '+255700000206',
          role: AccountRole.customer,
          verification: AccountVerification.verified,
        ),
      );
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
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back, Review'), findsOneWidget);
      final sidebar = find.byKey(const Key('customer-portal-sidebar'));
      await tester.tap(
        find.descendant(
          of: sidebar,
          matching: find.text('Unlocked properties'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No unlocked properties'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Back to marketplace'),
        200,
        scrollable: find.descendant(
          of: sidebar,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.text('Back to marketplace'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nav-explore')), findsOneWidget);
      expect(store.currentUser, isNotNull);
    },
  );

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
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _storeWithTestRental();
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

    await tester.tap(find.byKey(const Key('nav-rentals')));
    await tester.pumpAndSettle();
    final rentalCardTitle = find.text('Test Mbezi Beach Home');
    await tester.ensureVisible(rentalCardTitle);
    await tester.pumpAndSettle();
    await tester.tap(rentalCardTitle);
    await tester.pumpAndSettle();

    final detailScreen = find.byType(PropertyDetailScreen);
    expect(detailScreen, findsOneWidget);
    final title = find.descendant(
      of: detailScreen,
      matching: find.text('Test Mbezi Beach Home'),
    );
    expect(title, findsOneWidget);
    expect(tester.getTopLeft(title).dy, lessThan(500));
    expect(
      find.descendant(
        of: detailScreen,
        matching: find.text('Exact location & contact'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('rental details show locked access without leaking address', (
    tester,
  ) async {
    final store = _storeWithTestRental();
    addTearDown(store.dispose);
    await store.loadProperties();
    final rental = store.propertyById('test-rental')!;

    await tester.pumpWidget(
      MaterialApp(
        home: PropertyDetailScreen(property: rental, store: store),
      ),
    );
    await tester.pump();
    final propertyTitle = find.text('Test Mbezi Beach Home');
    expect(propertyTitle, findsOneWidget);
    expect(tester.getTopLeft(propertyTitle).dy, lessThan(500));
    expect(find.text('Exact location & contact'), findsOneWidget);
    expect(find.textContaining('Plot 18, Bahari Road'), findsNothing);
    final propertyMap = tester.widget<PropertyMapFrame>(
      find.byType(PropertyMapFrame),
    );
    expect(propertyMap.locationQuery, rental.generalLocation);
  });

  test('Tanzanian pricing config formats the booking fee clearly', () {
    const stayPrice = 800000;
    final bookingFee = (stayPrice * BusinessConfig.bookingFeeRate).round();

    expect(bookingFee, 16000);
    expect(formatTzs(stayPrice + bookingFee), contains('816,000'));
    expect(BusinessConfig.defaultUnlockFeeTzs, 5000);
  });

  test('rental contact stays locked until a recorded unlock', () async {
    final store = _storeWithTestRental();
    addTearDown(store.dispose);
    await store.loadProperties();
    final rental = store.propertyById('test-rental')!;

    expect(await store.contactFor(rental.id), isNull);
    await store.recordUnlock(rental);
    expect((await store.contactFor(rental.id))?.contactName, 'Test owner');

    await store.recordUnlock(rental);
    expect(store.unlockedProperties, hasLength(1));
  });

  testWidgets('successful rental preview payment reveals contact', (
    tester,
  ) async {
    final store = _storeWithTestRental();
    addTearDown(store.dispose);
    store.startPreviewSession();
    await store.loadProperties();
    final rental = store.propertyById('test-rental')!;

    await tester.pumpWidget(
      MaterialApp(
        home: CheckoutScreen(property: rental, store: store),
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pay '));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Location and contact unlocked'), findsOneWidget);
    expect(find.textContaining('Test address, Mbezi Beach'), findsOneWidget);
    expect(store.unlockedProperties, hasLength(1));
  });
}

HavenLinkStore _storeWithTestRental() => HavenLinkStore(
  repository: MockPropertyRepository(
    properties: const [_testRental],
    authorizedContacts: const {
      'test-rental': OwnerContact(
        exactAddress: 'Test address, Mbezi Beach',
        contactName: 'Test owner',
        role: 'Property owner',
        phone: '+255700000001',
        whatsApp: '+255700000001',
        latitude: -6.7,
        longitude: 39.2,
      ),
    },
  ),
);

const _testRental = Property(
  id: 'test-rental',
  name: 'Test Mbezi Beach Home',
  city: 'Dar es Salaam',
  neighborhood: 'Mbezi Beach',
  priceTzs: 650000,
  businessModel: PropertyBusinessModel.contactUnlock,
  category: PropertyCategory.house,
  imageUrl: 'https://example.invalid/test-home.jpg',
  rating: 0,
  reviewCount: 0,
  bedrooms: 2,
  bathrooms: 1,
  amenities: ['Parking', 'Water'],
  description: 'A test rental fixture with a private owner contact.',
  available: true,
  furnished: false,
  parking: true,
  water: true,
  electricity: true,
  security: true,
  propertyVerification: VerificationStatus.verified,
  ownerVerification: VerificationStatus.verified,
  managerName: 'Test owner',
);

Future<void> _expectPortalOpensAfterSignIn(
  WidgetTester tester,
  AccountRole role, {
  bool wide = false,
}) async {
  if (wide) {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  final store = HavenLinkStore(authentication: _RoleAuthentication(role));
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
  await tester.tap(find.text(wide ? 'Log in' : 'Account'));
  await tester.pumpAndSettle();
  if (!wide) {
    await tester.tap(find.text('Sign in or create an account'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byType(TextFormField).at(0), 'review@hl.test');
  await tester.enterText(find.byType(TextFormField).at(1), 'Demo1234');
  await tester.ensureVisible(find.byKey(const Key('auth-submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('auth-submit')));
  await tester.pumpAndSettle();

  final portalEntry = find.text(switch (role) {
    AccountRole.rentalAgent => 'My Listings',
    AccountRole.stayAgent => 'Dashboard',
    AccountRole.admin => 'Overview',
    AccountRole.customer => 'Your account',
  });
  expect(
    portalEntry,
    role == AccountRole.admin && wide ? findsWidgets : findsOneWidget,
  );
  if (role == AccountRole.rentalAgent) {
    expect(find.text('Inquiries'), findsNothing);
    expect(find.text('Recent inquiries'), findsNothing);
  }
  if (wide) {
    expect(
      find.ancestor(
        of: find.text(
          role == AccountRole.rentalAgent ? 'My Listings' : 'Overview',
        ),
        matching: find.byType(ListTile),
      ),
      findsOneWidget,
    );
  }
  expect(find.byTooltip('Back'), findsNothing);
  expect(find.byTooltip('Sign out'), findsOneWidget);
  await tester.tap(find.byTooltip('Sign out'));
  await tester.pumpAndSettle();
  expect(store.isSignedIn, isFalse);
  expect(find.byType(HomeScreen), findsOneWidget);
  expect(find.text('Your account'), findsNothing);
}

class _RoleAuthentication implements AuthenticationRepository {
  _RoleAuthentication(this.role);

  final AccountRole role;

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
    id: 'test-${role.identifier}',
    fullName: 'Test Agent',
    email: email,
    phone: '+255700000202',
    role: role,
    verification: AccountVerification.verified,
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
