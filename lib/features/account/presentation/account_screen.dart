import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/config/env_config.dart';
import '../../notifications/presentation/notification_center_screen.dart';
import '../../notifications/presentation/rental_statements_screen.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/portal_page_header.dart';
import '../../../core/widgets/portal_sidebar.dart';
import '../../../core/widgets/portal_scaffold.dart';
import '../../../core/widgets/metric_card.dart';
import '../../account/domain/account_models.dart';
import '../data/customer_data_repository.dart';
import '../../access/domain/access_control.dart';
import '../../auth/presentation/auth_screen.dart';
import 'booking_details_screen.dart';
import 'rental_messages_screen.dart';
import '../../properties/domain/property.dart';
import '../../properties/presentation/widgets/property_card.dart';
import '../../properties/presentation/widgets/property_photo.dart';
import '../../reviews/presentation/customer_reviews_tab.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    required this.store,
    required this.onOpenProperty,
    this.onOpenPortal,
    this.onBackToMarketplace,
    super.key,
  });

  final HavenLinkStore store;
  final ValueChanged<Property> onOpenProperty;
  final ValueChanged<Portal>? onOpenPortal;
  final VoidCallback? onBackToMarketplace;

  @override
  Widget build(BuildContext context) {
    if (!store.isSignedIn) {
      return SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      HavenIcons.accountCircleOutlined,
                      color: HavenTheme.forest,
                      size: 46,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.tr('Your Haven Link account'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr(
                        'Keep bookings, saved homes and unlocked owner contacts together.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: () async {
                        final user = await Navigator.of(context).push<User>(
                          MaterialPageRoute<User>(
                            builder: (context) => AuthScreen(store: store),
                          ),
                        );
                        final portal = _portalForUser(user);
                        if (portal != null) {
                          onOpenPortal?.call(portal);
                        }
                      },
                      icon: const Icon(HavenIcons.login),
                      label: Text(context.tr('Sign in or create an account')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final rolePortal = _portalForRole(store.currentUser?.role);
    if (rolePortal != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: PortalPageHeader(
          eyebrow: context.tr(rolePortal.title),
          title: store.currentUser?.fullName ?? context.tr('Your account'),
          subtitle: store.customerEmail ?? '',
          icon: HavenIcons.workspacesOutline,
        ),
      );
    }

    if (MediaQuery.sizeOf(context).width >= 1024) {
      return _CustomerWorkspace(
        store: store,
        onOpenProperty: onOpenProperty,
        onBackToMarketplace: onBackToMarketplace,
      );
    }

    return DefaultTabController(
      length: 6,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PortalPageHeader(
              action: onBackToMarketplace == null
                  ? null
                  : FilledButton.icon(
                      onPressed: onBackToMarketplace,
                      icon: const Icon(HavenIcons.search, size: 16),
                      label: Text(context.tr('Find a space')),
                    ),
              eyebrow: context.tr('Customer portal'),
              title: context.tr('Your account'),
              subtitle: store.customerEmail ?? context.tr('Preview customer'),
              icon: HavenIcons.personOutline,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: TextButton.icon(
                  onPressed: store.signOut,
                  icon: const Icon(HavenIcons.logout, size: 17),
                  label: Text(context.tr('Sign out')),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _AccountMetric(
                  label: context.tr('Bookings'),
                  value: store.bookings.length.toString(),
                ),
                _AccountMetric(
                  label: context.tr('Unlocked'),
                  value: store.unlockedProperties.length.toString(),
                ),
                _AccountMetric(
                  label: context.tr('Saved'),
                  value: store.savedPropertyIds.length.toString(),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: context.tr('My bookings')),
                Tab(text: 'My trips'),
                Tab(text: context.tr('Unlocked properties')),
                Tab(text: context.tr('Saved')),
                Tab(text: context.tr('Recently viewed')),
                Tab(text: context.tr('Payments')),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 460,
              child: TabBarView(
                children: [
                  _BookingsTab(store: store),
                  CustomerReviewsTab(
                    tokenProvider: () =>
                        store.authenticationRepository.accessToken,
                  ),
                  _UnlockedTab(store: store, onOpenProperty: onOpenProperty),
                  _PropertyTab(
                    properties: store.properties
                        .where(
                          (property) =>
                              store.savedPropertyIds.contains(property.id),
                        )
                        .toList(),
                    store: store,
                    onOpenProperty: onOpenProperty,
                    emptyTitle: context.tr('No saved properties yet'),
                    emptyMessage: context.tr(
                      'Save a listing to keep it close at hand.',
                    ),
                  ),
                  _PropertyTab(
                    properties: store.recentlyViewed,
                    store: store,
                    onOpenProperty: onOpenProperty,
                    emptyTitle: context.tr('Nothing viewed yet'),
                    emptyMessage: context.tr(
                      'Properties you open will appear here.',
                    ),
                  ),
                  _PaymentsTab(store: store),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 4,
              children: [
                _AccountLink(
                  icon: HavenIcons.chatBubbleOutline,
                  label: context.tr('Messages'),
                  onTap: () => _openCustomerMessages(context, store),
                ),
                if (EnvConfig.backendConfigured &&
                    store.currentUser != null) ...[
                  _AccountLink(
                    icon: HavenIcons.notificationsNone,
                    label: context.tr('Notifications'),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => NotificationCenterScreen(
                          repository: NotificationRepository(
                            tokenProvider: () =>
                                store.authenticationRepository.accessToken,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _TenantStatementsLink(
                    repository: NotificationRepository(
                      tokenProvider: () =>
                          store.authenticationRepository.accessToken,
                    ),
                  ),
                ],
                _AccountLink(
                  icon: HavenIcons.helpOutline,
                  label: context.tr('Help & support'),
                ),
                if (store.currentUser?.role == AccountRole.rentalAgent ||
                    (store.currentUser?.hasCapability(
                          AgentCapability.rentalProperty,
                        ) ??
                        false))
                  _AccountLink(
                    icon: HavenIcons.homeWorkOutlined,
                    label: 'Rental Agent Portal',
                    onTap: () => onOpenPortal?.call(Portal.rentalAgent),
                  ),
                if (store.currentUser != null &&
                    AccessControl.canOpenPortal(
                      store.currentUser,
                      Portal.apartmentAgent,
                    ) &&
                    store.currentUser?.role != AccountRole.admin)
                  _AccountLink(
                    icon: HavenIcons.apartmentOutlined,
                    label: 'Apartment Stays Portal',
                    onTap: () => onOpenPortal?.call(Portal.apartmentAgent),
                  ),
                if (store.currentUser != null &&
                    AccessControl.canOpenPortal(
                      store.currentUser,
                      Portal.stayAgent,
                    ) &&
                    store.currentUser?.role != AccountRole.admin)
                  _AccountLink(
                    icon: HavenIcons.hotelOutlined,
                    label: 'Hotel, Lodge & Motel Portal',
                    onTap: () => onOpenPortal?.call(Portal.stayAgent),
                  ),
                if (store.currentUser?.role == AccountRole.admin)
                  _AccountLink(
                    icon: HavenIcons.adminPanelSettings,
                    label: 'Admin Dashboard',
                    onTap: () => onOpenPortal?.call(Portal.admin),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerWorkspace extends StatelessWidget {
  const _CustomerWorkspace({
    required this.store,
    required this.onOpenProperty,
    this.onBackToMarketplace,
  });

  final HavenLinkStore store;
  final ValueChanged<Property> onOpenProperty;
  final VoidCallback? onBackToMarketplace;

  @override
  Widget build(BuildContext context) {
    final labels = [
      context.tr('Overview'),
      context.tr('My bookings'),
      context.tr('My trips'),
      context.tr('Unlocked properties'),
      context.tr('Saved'),
      context.tr('Recently viewed'),
      context.tr('Payments'),
    ];
    const icons = [
      HavenIcons.dashboardOutlined,
      HavenIcons.luggageOutlined,
      HavenIcons.rateReviewOutlined,
      HavenIcons.keyOutlined,
      HavenIcons.favoriteBorder,
      HavenIcons.history,
      HavenIcons.receiptLongOutlined,
    ];
    return DefaultTabController(
      length: labels.length,
      child: Builder(
        builder: (context) {
          final tabs = DefaultTabController.of(context);
          return AnimatedBuilder(
            animation: tabs,
            builder: (context, _) => Row(
              children: [
                SizedBox(
                  width: 250,
                  child: Material(
                    color: HavenTheme.white,
                    child: SafeArea(
                      child: ListView(
                        key: const Key('customer-portal-sidebar'),
                        padding: const EdgeInsets.all(20),
                        children: [
                          PortalSidebarHeading(
                            workspace: context.tr('Customer portal'),
                          ),
                          for (var index = 0; index < labels.length; index++)
                            PortalSidebarItem(
                              icon: icons[index],
                              label: labels[index],
                              selected: tabs.index == index,
                              onTap: () => tabs.animateTo(index),
                            ),
                          PortalSidebarItem(
                            icon: HavenIcons.chatBubbleOutline,
                            label: context.tr('Messages'),
                            selected: false,
                            onTap: () => _openCustomerMessages(context, store),
                          ),
                          if (EnvConfig.backendConfigured) ...[
                            PortalSidebarItem(
                              icon: HavenIcons.notificationsNone,
                              label: context.tr('Notifications'),
                              selected: false,
                              onTap: () => Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => NotificationCenterScreen(
                                    repository: NotificationRepository(
                                      tokenProvider: () => store
                                          .authenticationRepository
                                          .accessToken,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _TenantStatementsLink(
                              repository: NotificationRepository(
                                tokenProvider: () =>
                                    store.authenticationRepository.accessToken,
                              ),
                            ),
                          ],
                          _AccountLink(
                            icon: HavenIcons.helpOutline,
                            label: context.tr('Help & support'),
                          ),
                          if (onBackToMarketplace != null)
                            TextButton.icon(
                              onPressed: onBackToMarketplace,
                              icon: const Icon(
                                HavenIcons.chevronLeft,
                                size: 16,
                              ),
                              label: Text(context.tr('Back to marketplace')),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 70,
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        decoration: const BoxDecoration(
                          color: HavenTheme.white,
                          border: Border(
                            bottom: BorderSide(color: HavenTheme.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: PortalHeaderTitle(
                                title: labels[tabs.index],
                                destinations: labels,
                                onDestination: tabs.animateTo,
                              ),
                            ),
                            NotificationBellButton(
                              tokenProvider: () =>
                                  store.authenticationRepository.accessToken,
                            ),
                            PortalAvatar(
                              name: store.currentUser?.fullName ?? '',
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              tooltip: context.tr('Sign out'),
                              onPressed: () {
                                store.signOut();
                                onBackToMarketplace?.call();
                              },
                              icon: const Icon(HavenIcons.logout),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: TabBarView(
                            children: [
                              _CustomerOverview(
                                store: store,
                                onViewBookings: () => tabs.animateTo(1),
                                onFindSpace: onBackToMarketplace,
                              ),
                              _BookingsTab(store: store),
                              CustomerReviewsTab(
                                tokenProvider: () =>
                                    store.authenticationRepository.accessToken,
                              ),
                              _UnlockedTab(
                                store: store,
                                onOpenProperty: onOpenProperty,
                              ),
                              _PropertyTab(
                                properties: store.properties
                                    .where(
                                      (property) => store.savedPropertyIds
                                          .contains(property.id),
                                    )
                                    .toList(),
                                store: store,
                                onOpenProperty: onOpenProperty,
                                emptyTitle: context.tr(
                                  'No saved properties yet',
                                ),
                                emptyMessage: context.tr(
                                  'Save a listing to keep it close at hand.',
                                ),
                              ),
                              _PropertyTab(
                                properties: store.recentlyViewed,
                                store: store,
                                onOpenProperty: onOpenProperty,
                                emptyTitle: context.tr('Nothing viewed yet'),
                                emptyMessage: context.tr(
                                  'Properties you open will appear here.',
                                ),
                              ),
                              _PaymentsTab(store: store),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CustomerOverview extends StatelessWidget {
  const _CustomerOverview({
    required this.store,
    required this.onViewBookings,
    this.onFindSpace,
  });
  final VoidCallback? onFindSpace;

  final HavenLinkStore store;
  final VoidCallback onViewBookings;

  @override
  Widget build(BuildContext context) {
    final firstName = store.currentUser?.fullName.trim().split(' ').first ?? '';
    final metrics = [
      (
        context.tr('Bookings'),
        store.bookings.length,
        HavenIcons.luggageOutlined,
      ),
      (
        context.tr('Unlocked'),
        store.unlockedProperties.length,
        HavenIcons.keyOutlined,
      ),
      (
        context.tr('Saved'),
        store.savedPropertyIds.length,
        HavenIcons.favoriteBorder,
      ),
    ];
    return ListView(
      children: [
        PortalPageHeader(
          action: onFindSpace == null
              ? null
              : FilledButton.icon(
                  onPressed: onFindSpace,
                  icon: const Icon(HavenIcons.search, size: 16),
                  label: Text(context.tr('Find a space')),
                ),
          eyebrow: context.tr('Customer portal'),
          title: firstName.isEmpty
              ? context.tr('Your account')
              : '${context.tr('Welcome back')}, $firstName',
          subtitle: context.tr(
            'Keep bookings, saved homes and unlocked owner contacts together.',
          ),
          icon: HavenIcons.personOutline,
        ),
        const SizedBox(height: 28),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 700 ? 3 : 1;
            final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (label, value, icon) in metrics)
                  SizedBox(
                    width: width,
                    child: HavenMetricCard(
                      label: label,
                      value: '$value',
                      icon: icon,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('My bookings'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: onViewBookings,
                      child: Text(context.tr('View all')),
                    ),
                  ],
                ),
                SizedBox(height: 260, child: _BookingsTab(store: store)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

void _openCustomerMessages(BuildContext context, HavenLinkStore store) {
  final userId = store.currentUser?.id;
  if (userId == null) return;
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => RentalMessagesScreen(
        repository: CustomerDataRepository(
          tokenProvider: () => store.authenticationRepository.accessToken,
        ),
        currentUserId: userId,
        isAgent: false,
      ),
    ),
  );
}

/// First portal the user may open, or null for customers.
Portal? _portalForUser(User? user) {
  if (user == null) return null;
  if (user.role == AccountRole.admin) return Portal.admin;
  if (user.role == AccountRole.customer) return null;
  final options = AccessControl.allowedPortals(user);
  return options.isEmpty ? _portalForRole(user.role) : options.first;
}

Portal? _portalForRole(AccountRole? role) => switch (role) {
  AccountRole.rentalAgent => Portal.rentalAgent,
  AccountRole.stayAgent => Portal.stayAgent,
  AccountRole.admin => Portal.admin,
  _ => null,
};

class _BookingsTab extends StatelessWidget {
  const _BookingsTab({required this.store});

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    if (store.bookings.isEmpty) {
      return _EmptyTab(
        icon: HavenIcons.luggageOutlined,
        title: context.tr('No bookings yet'),
        message: context.tr(
          'Your confirmed hotels, lodges and apartments will appear here.',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 10),
      itemCount: store.bookings.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final booking = store.bookings[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (context) =>
                    BookingDetailsScreen(booking: booking, store: store),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: PropertyPhoto(
                      imageUrl: booking.property.imageUrl,
                      height: 74,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.property.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${booking.roomTypeName ?? 'Accommodation'}'
                          '${booking.assignedRoomNumber == null ? '' : ' · Room ${booking.assignedRoomNumber}'}',
                        ),
                        Text(
                          '${_date(booking.checkIn)} – ${_date(booking.checkOut)} · ${booking.guestCount} ${booking.guestCount == 1 ? 'guest' : 'guests'}',
                          style: const TextStyle(
                            color: HavenTheme.muted,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '${_bookingStatusLabel(booking.status)} · ${booking.paymentTransactionId == null ? 'Payment pending' : 'Payment verified'}',
                          style: const TextStyle(
                            color: HavenTheme.forest,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatTzs(booking.totalTzs),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Icon(HavenIcons.chevronRight),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UnlockedTab extends StatelessWidget {
  const _UnlockedTab({required this.store, required this.onOpenProperty});

  final HavenLinkStore store;
  final ValueChanged<Property> onOpenProperty;

  @override
  Widget build(BuildContext context) {
    if (store.unlockedProperties.isEmpty) {
      return _EmptyTab(
        icon: HavenIcons.keyOutlined,
        title: context.tr('No unlocked properties'),
        message:
            'Rental addresses and verified owner or agent contacts you unlock will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 10),
      itemCount: store.unlockedProperties.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final unlocked = store.unlockedProperties[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(HavenIcons.homeOutlined),
                  ),
                  title: Text(unlocked.property.name),
                  subtitle: Text(
                    '${unlocked.property.generalLocation} · ${formatTzs(unlocked.property.priceTzs)}/month',
                  ),
                  trailing: IconButton(
                    tooltip: 'View property',
                    onPressed: () => onOpenProperty(unlocked.property),
                    icon: const Icon(HavenIcons.arrowForward),
                  ),
                ),
                Text(
                  'Unlocked ${_date(unlocked.unlockedAt)}',
                  style: const TextStyle(color: HavenTheme.muted),
                ),
                const SizedBox(height: 10),
                FutureBuilder<OwnerContact?>(
                  future: store.contactFor(unlocked.property.id),
                  builder: (context, snapshot) {
                    final contact = snapshot.data;
                    if (contact == null) return const LinearProgressIndicator();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(contact.exactAddress),
                        Text('${contact.contactName} · ${contact.role}'),
                        Text(contact.phone),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            final userId = store.currentUser?.id;
                            if (userId == null) return;
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (context) => RentalMessagesScreen(
                                  repository: CustomerDataRepository(
                                    tokenProvider: () => store
                                        .authenticationRepository
                                        .accessToken,
                                  ),
                                  currentUserId: userId,
                                  isAgent: false,
                                  listingId: unlocked.property.id,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(HavenIcons.chatBubbleOutline),
                          label: const Text('Message Rental Agent'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PropertyTab extends StatelessWidget {
  const _PropertyTab({
    required this.properties,
    required this.store,
    required this.onOpenProperty,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final List<Property> properties;
  final HavenLinkStore store;
  final ValueChanged<Property> onOpenProperty;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (properties.isEmpty) {
      return _EmptyTab(
        icon: HavenIcons.homeOutlined,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 10),
      itemCount: properties.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => PropertyCard(
        property: properties[index],
        store: store,
        onTap: () => onOpenProperty(properties[index]),
      ),
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({required this.store});

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    if (store.paymentRecords.isEmpty) {
      return _EmptyTab(
        icon: HavenIcons.receiptLongOutlined,
        title: context.tr('No payment history'),
        message: 'Preview booking and unlock transactions will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 10),
      itemCount: store.paymentRecords.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final payment = store.paymentRecords[index];
        return Card(
          child: ListTile(
            leading: const Icon(HavenIcons.receiptLongOutlined),
            title: Text(payment.purpose),
            subtitle: Text(
              '${payment.property.name} · ${payment.method}\n${payment.reference}',
            ),
            isThreeLine: true,
            trailing: Text(
              formatTzs(payment.amountTzs),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        );
      },
    );
  }
}

class _AccountMetric extends StatelessWidget {
  const _AccountMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(
        radius: 10,
        backgroundColor: HavenTheme.forest,
        child: Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ),
      label: Text(label),
    );
  }
}

class _TenantStatementsLink extends StatefulWidget {
  const _TenantStatementsLink({required this.repository});

  final NotificationRepository repository;

  @override
  State<_TenantStatementsLink> createState() => _TenantStatementsLinkState();
}

class _TenantStatementsLinkState extends State<_TenantStatementsLink> {
  bool _hasStatements = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final items = await widget.repository.rentalStatements();
      if (mounted && items.isNotEmpty) setState(() => _hasStatements = true);
    } on StateError {
      // Not a linked tenant, or offline: keep the link hidden.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasStatements) return const SizedBox.shrink();
    return _AccountLink(
      icon: HavenIcons.receiptLongOutlined,
      label: context.tr('Rental payments'),
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => RentalStatementsScreen(repository: widget.repository),
        ),
      ),
    );
  }
}

class _AccountLink extends StatelessWidget {
  const _AccountLink({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed:
          onTap ??
          () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(label),
              content: const Text(
                'This account service is ready to connect to Haven Link backend APIs.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: HavenTheme.muted),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';

String _bookingStatusLabel(BookingStatus status) => switch (status) {
  BookingStatus.active => 'Confirmed',
  BookingStatus.pending => 'Pending',
  BookingStatus.completed => 'Completed',
  BookingStatus.cancelled => 'Cancelled',
};
