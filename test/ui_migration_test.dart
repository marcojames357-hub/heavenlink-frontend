import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haven_link/core/state/haven_link_store.dart';
import 'package:haven_link/core/theme/app_theme.dart';
import 'package:haven_link/core/widgets/portal_sidebar.dart';
import 'package:haven_link/features/access/domain/access_control.dart';
import 'package:haven_link/features/account/domain/account_models.dart';
import 'package:haven_link/features/account/presentation/account_screen.dart';
import 'package:haven_link/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:haven_link/features/agent_portal/presentation/accommodation_agent_dashboard_screen.dart';
import 'package:haven_link/features/agent_portal/presentation/rental_agent_dashboard_screen.dart';
import 'package:haven_link/features/agent_portal/state/agent_portal_store.dart';
import 'package:haven_link/features/auth/domain/authentication_repository.dart';
import 'package:haven_link/features/auth/presentation/auth_screen.dart';
import 'package:haven_link/features/checkout/presentation/checkout_screen.dart';
import 'package:haven_link/features/home/presentation/haven_link_shell.dart';
import 'package:haven_link/features/properties/data/property_repository.dart';
import 'package:haven_link/features/properties/domain/property.dart';
import 'package:haven_link/features/properties/presentation/property_detail_screen.dart';
import 'package:haven_link/features/search/presentation/property_browse_screen.dart';

const _capture = bool.fromEnvironment('CAPTURE_UI');
const _frame = Key('capture-frame');
const _rental = Property(
  id: 'rental',
  name: 'Garden home',
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
  amenities: ['Garden', 'Parking'],
  description: 'A comfortable home close to local shops.',
  available: true,
  furnished: false,
  parking: true,
  water: true,
  electricity: true,
  security: true,
  propertyVerification: VerificationStatus.unverified,
  ownerVerification: VerificationStatus.unverified,
  managerName: 'Agent',
);
const _apartment = Property(
  id: 'apartment',
  name: 'Masaki apartment',
  city: 'Dar es Salaam',
  neighborhood: 'Masaki',
  priceTzs: 150000,
  businessModel: PropertyBusinessModel.bookable,
  category: PropertyCategory.shortStayApartment,
  imageUrl: '',
  rating: 0,
  reviewCount: 0,
  bedrooms: 2,
  bathrooms: 1,
  amenities: ['Garden', 'Parking'],
  description: 'A comfortable home close to local shops.',
  available: true,
  furnished: false,
  parking: true,
  water: true,
  electricity: true,
  security: true,
  propertyVerification: VerificationStatus.unverified,
  ownerVerification: VerificationStatus.unverified,
  managerName: 'Agent',
);

class _Auth implements AuthenticationRepository {
  _Auth(this.role, this.workspaces);
  final AccountRole role;
  final Set<AgentWorkspace> workspaces;
  @override
  String get label => 'Test fixture';
  @override
  String? get accessToken => null;
  @override
  bool get isConfigured => true;
  @override
  Future<User> signIn({
    required String email,
    required String password,
  }) async => User(
    id: 'ui-${role.name}',
    fullName: 'Amina Mhando',
    email: email,
    phone: '+255700000001',
    role: role,
    workspaces: workspaces,
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

HavenLinkStore _store({
  AccountRole role = AccountRole.customer,
  Set<AgentWorkspace> workspaces = const {},
}) {
  final store = HavenLinkStore(
    repository: MockPropertyRepository(properties: [_rental, _apartment]),
    authentication: _Auth(role, workspaces),
  );
  addTearDown(store.dispose);
  return store;
}

Future<void> _pump(WidgetTester tester, Widget page, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _frame,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: HavenTheme.light,
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _snapshot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull, reason: name);
  if (!_capture) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_frame),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('../migration-backups/previews');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    for (final (family, asset) in [
      ('Inter', 'assets/fonts/Inter-Variable.ttf'),
      ('HavenSerif', 'assets/fonts/LibreCaslonText-Italic.ttf'),
      (
        'packages/lucide_icons_flutter/Lucide',
        'packages/lucide_icons_flutter/assets/lucide.ttf',
      ),
      ('MaterialIcons', 'fonts/MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(family)..addFont(rootBundle.load(asset));
      await loader.load();
    }
  });

  testWidgets(
    'homepage query and category selections reach existing browse filters',
    (tester) async {
      addTearDown(tester.view.reset);
      final store = _store();
      await _pump(
        tester,
        HavenLinkShell(
          store: store,
          locale: const Locale('en'),
          onLocaleChanged: (_) {},
        ),
        const Size(1280, 900),
      );
      await tester.enterText(
        find.byKey(const Key('home-search-location')),
        'Masaki',
      );
      await tester.tap(find.byKey(const Key('home-search-submit')));
      await tester.pumpAndSettle();
      final browse = tester.widget<PropertyBrowseScreen>(
        find.byType(PropertyBrowseScreen),
      );
      expect(browse.initialQuery, 'Masaki');
      expect(browse.businessModel, PropertyBusinessModel.bookable);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('home-category-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-category-1')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PropertyBrowseScreen>(find.byType(PropertyBrowseScreen))
            .initialCategory,
        'apartment',
      );
      expect(find.text('Garden home'), findsNothing);
    },
  );

  testWidgets(
    'affordable stays are visible without changing the default price filter',
    (tester) async {
      addTearDown(tester.view.reset);
      final motel = _apartment.copyWith(
        name: 'Roadside demo motel',
        category: PropertyCategory.motel,
        priceTzs: 60000,
      );
      final store = HavenLinkStore(
        repository: MockPropertyRepository(properties: [motel]),
      );
      addTearDown(store.dispose);
      await _pump(
        tester,
        Scaffold(
          body: PropertyBrowseScreen(
            store: store,
            businessModel: PropertyBusinessModel.bookable,
            onOpenProperty: (_) {},
          ),
        ),
        const Size(390, 844),
      );
      expect(find.text('Roadside demo motel'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 720),
    const Size(768, 1024),
    const Size(1440, 1000),
  ]) {
    final suffix = '${size.width.toInt()}';
    testWidgets(
      'complete customer pages fit $suffix with the production theme',
      (tester) async {
        addTearDown(tester.view.reset);
        final store = _store();
        final homeStore = HavenLinkStore(
          repository: MockPropertyRepository(properties: const []),
        );
        addTearDown(homeStore.dispose);
        await _pump(
          tester,
          HavenLinkShell(
            store: homeStore,
            locale: const Locale('en'),
            onLocaleChanged: (_) {},
          ),
          size,
        );
        await _snapshot(tester, 'home-$suffix');
        final scroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const Key('home-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        for (
          double offset = 400;
          offset < scroll.position.maxScrollExtent;
          offset += 400
        ) {
          scroll.position.jumpTo(offset);
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'home $suffix offset $offset',
          );
        }
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        await _snapshot(tester, 'home-footer-$suffix');
        for (final (name, page) in <(String, Widget)>[
          ('auth', AuthScreen(store: store)),
          (
            'registration',
            AuthScreen(
              key: ValueKey('registration-$suffix'),
              store: store,
              initialRegister: true,
            ),
          ),
          (
            'rentals',
            Scaffold(
              body: PropertyBrowseScreen(
                store: store,
                businessModel: PropertyBusinessModel.contactUnlock,
                onOpenProperty: (_) {},
              ),
            ),
          ),
          (
            'stays',
            Scaffold(
              body: PropertyBrowseScreen(
                store: store,
                businessModel: PropertyBusinessModel.bookable,
                onOpenProperty: (_) {},
              ),
            ),
          ),
          (
            'rental-detail',
            PropertyDetailScreen(property: _rental, store: store),
          ),
          (
            'apartment-detail',
            PropertyDetailScreen(property: _apartment, store: store),
          ),
          ('checkout', CheckoutScreen(property: _rental, store: store)),
        ]) {
          await _pump(tester, page, size);
          await _snapshot(tester, '$name-$suffix');
        }
        await store.signIn(email: 'customer@hl.test', password: 'test');
        await _pump(
          tester,
          Scaffold(
            body: AccountScreen(
              store: store,
              onOpenProperty: (_) {},
              onBackToMarketplace: () {},
            ),
          ),
          size,
        );
        await _snapshot(tester, 'customer-$suffix');
      },
    );
  }

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    for (final (portal, role, workspace) in [
      (Portal.rentalAgent, AccountRole.rentalAgent, AgentWorkspace.rental),
      (Portal.apartmentAgent, AccountRole.stayAgent, AgentWorkspace.apartment),
      (Portal.stayAgent, AccountRole.stayAgent, AgentWorkspace.hotel),
      (Portal.admin, AccountRole.admin, AgentWorkspace.hotel),
    ]) {
      testWidgets('${portal.name} pages retain navigation at ${size.width}', (
        tester,
      ) async {
        addTearDown(tester.view.reset);
        final store = _store(role: role, workspaces: {workspace});
        await store.signIn(email: 'agent@hl.test', password: 'test');
        final agent = AgentPortalStore(store: store, portal: portal);
        addTearDown(agent.dispose);
        final page = switch (portal) {
          Portal.rentalAgent => RentalAgentDashboardScreen(
            store: store,
            agentStore: agent,
          ),
          Portal.apartmentAgent => ApartmentAgentDashboardScreen(
            store: store,
            agentStore: agent,
          ),
          Portal.stayAgent => StayAgentDashboardScreen(
            store: store,
            agentStore: agent,
          ),
          Portal.admin => AdminDashboardScreen(store: store),
        };
        await _pump(tester, page, size);
        await _snapshot(tester, '${portal.name}-${size.width.toInt()}');
        if (size.width < 1000) {
          await tester.tap(find.byTooltip('Open navigation menu'));
          await tester.pumpAndSettle();
        }
        final sidebar = find.byKey(const Key('portal-sidebar'));
        expect(sidebar, findsOneWidget);
        // Discover each existing destination, then open it through the same
        // sidebar used in production. No route or permission mocks are added.
        final labels = <String>[];
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: sidebar, matching: find.byType(Scrollable)).first,
        );
        for (
          double offset = 0;
          offset <= scroll.position.maxScrollExtent + 300;
          offset += 300
        ) {
          scroll.position.jumpTo(
            offset.clamp(0, scroll.position.maxScrollExtent),
          );
          await tester.pump();
          for (final item in tester.widgetList<PortalSidebarItem>(
            find.descendant(
              of: sidebar,
              matching: find.byType(PortalSidebarItem),
            ),
          )) {
            if (!labels.contains(item.label)) labels.add(item.label);
          }
        }
        for (final label in labels) {
          if (size.width < 1000 && find.byType(Drawer).evaluate().isEmpty) {
            await tester.tap(find.byTooltip('Open navigation menu'));
            await tester.pumpAndSettle();
          }
          final target = find.descendant(
            of: find.byType(PortalSidebarItem),
            matching: find.text(label),
          );
          final scrollable = find
              .descendant(
                of: find.byKey(const Key('portal-sidebar')),
                matching: find.byType(Scrollable),
              )
              .first;
          tester.state<ScrollableState>(scrollable).position.jumpTo(0);
          await tester.pump();
          await tester.scrollUntilVisible(
            target,
            300,
            scrollable: scrollable,
            maxScrolls: 20,
          );
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          await tester.tap(target);
          await tester.pumpAndSettle();
          await _snapshot(
            tester,
            '${portal.name}-${size.width.toInt()}-${labels.indexOf(label)}',
          );
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
