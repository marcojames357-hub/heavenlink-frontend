import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/config/env_config.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/portal_sidebar.dart';
import '../../../core/widgets/portal_scaffold.dart';
import '../../account/domain/account_models.dart';
import '../../properties/domain/property.dart';
import '../../properties/presentation/property_detail_screen.dart';
import '../../properties/presentation/widgets/property_card.dart';
import '../../reviews/presentation/agent_reviews_tab.dart';
import '../../financial_management/presentation/financial_management_screen.dart';
import 'agent_dashboard_overview.dart';
import 'apartment_availability_tab.dart';
import '../../notifications/presentation/notification_center_screen.dart';
import 'listing_editor_dialog.dart';
import 'room_inventory_tab.dart';
import '../state/agent_portal_store.dart';

part 'apartment_agent_dashboard_screen.dart';

enum _StayNavGroup { main, property, business, communication, account }

enum _StaySection {
  dashboard,
  accommodations,
  bookings,
  messages,
  roomInventory,
  physicalRooms,
  availability,
  reviews,
  alerts,
  financial,
  utilities,
  profile,
}

const Map<_StayNavGroup, String> _hotelGroupLabels = {
  _StayNavGroup.main: 'Main',
  _StayNavGroup.property: 'Room management',
  _StayNavGroup.business: 'Financial management',
  _StayNavGroup.communication: 'Communication',
  _StayNavGroup.account: 'Account',
};

const Map<_StayNavGroup, String> _apartmentGroupLabels = {
  _StayNavGroup.main: 'Main',
  _StayNavGroup.property: 'Booking management',
  _StayNavGroup.business: 'Financial management',
  _StayNavGroup.communication: 'Communication',
  _StayNavGroup.account: 'Account',
};

class _StayNavItem {
  const _StayNavItem(this.section, this.label, this.icon, this.group);

  final _StaySection section;
  final String label;
  final IconData icon;
  final _StayNavGroup group;
}

const List<_StayNavItem> _stayNavItems = [
  _StayNavItem(
    _StaySection.dashboard,
    'Dashboard',
    LucideIcons.layoutDashboard,
    _StayNavGroup.main,
  ),
  _StayNavItem(
    _StaySection.accommodations,
    'My Properties',
    LucideIcons.building2,
    _StayNavGroup.main,
  ),
  _StayNavItem(
    _StaySection.roomInventory,
    'Room Categories',
    LucideIcons.tags,
    _StayNavGroup.property,
  ),
  _StayNavItem(
    _StaySection.physicalRooms,
    'Physical Rooms',
    LucideIcons.doorOpen,
    _StayNavGroup.property,
  ),
  _StayNavItem(
    _StaySection.availability,
    'Availability Calendar',
    LucideIcons.calendarDays,
    _StayNavGroup.property,
  ),
  _StayNavItem(
    _StaySection.bookings,
    'Reservations / Front Desk',
    LucideIcons.notebookPen,
    _StayNavGroup.property,
  ),
  _StayNavItem(
    _StaySection.financial,
    'Financial Overview',
    LucideIcons.wallet,
    _StayNavGroup.business,
  ),
  _StayNavItem(
    _StaySection.utilities,
    'Utilities & Expenses',
    LucideIcons.receiptText,
    _StayNavGroup.business,
  ),
  _StayNavItem(
    _StaySection.messages,
    'Messages',
    LucideIcons.messageCircle,
    _StayNavGroup.communication,
  ),
  _StayNavItem(
    _StaySection.reviews,
    'Reviews & Ratings',
    LucideIcons.star,
    _StayNavGroup.communication,
  ),
  _StayNavItem(
    _StaySection.alerts,
    'Alerts',
    LucideIcons.bell,
    _StayNavGroup.communication,
  ),
  _StayNavItem(
    _StaySection.profile,
    'Settings',
    LucideIcons.userRound,
    _StayNavGroup.account,
  ),
];

/// Dashboard for agents managing hotels, lodges and motels.
///
/// Apartments have their own [ApartmentAgentDashboardScreen].
class StayAgentDashboardScreen extends StatefulWidget {
  const StayAgentDashboardScreen({
    required this.store,
    required this.agentStore,
    super.key,
  });

  final HavenLinkStore store;
  final AgentPortalStore agentStore;

  @override
  State<StayAgentDashboardScreen> createState() =>
      _StayAgentDashboardScreenState();
}

class _StayAgentDashboardScreenState extends State<StayAgentDashboardScreen> {
  _StaySection _section = _StaySection.dashboard;

  _StayNavItem get _activeNav =>
      _navItems.firstWhere((item) => item.section == _section);

  /// The whole-unit date calendar belongs to the Apartment Stays portal;
  /// hotels manage availability through room inventory and reservations.
  List<_StayNavItem> get _navItems => _stayNavItems;

  String get _portalTitle => 'Hotel, Lodge & Motel Portal';

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onDataChanged);
    widget.agentStore.addListener(_onDataChanged);
    _loadBookings();
  }

  @override
  void didUpdateWidget(covariant StayAgentDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store
        ..removeListener(_onDataChanged)
        ..addListener(_onDataChanged);
    }
    if (oldWidget.agentStore != widget.agentStore) {
      oldWidget.agentStore
        ..removeListener(_onDataChanged)
        ..addListener(_onDataChanged);
      _loadBookings();
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onDataChanged);
    widget.agentStore.removeListener(_onDataChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.agentStore.isAuthorized) {
      return _UnauthorizedView();
    }

    final width = MediaQuery.of(context).size.width;
    final showSidebar = width >= 980;
    return HavenPortalScaffold(
      showSidebar: showSidebar,
      sidebar: _buildSidebar(context, false),
      appBar: AppBar(
        automaticallyImplyLeading: !showSidebar,
        title: showSidebar
            ? PortalHeaderTitle(
                title: _activeNav.label,
                destinations: _navItems.map((e) => e.label).toList(),
                onDestination: (index) =>
                    setState(() => _section = _navItems[index].section),
              )
            : Text(_activeNav.label),
        actions: [
          PortalAvatar(name: widget.store.currentUser?.fullName ?? ''),
          NotificationBellButton(
            tokenProvider: () =>
                widget.store.authenticationRepository.accessToken,
          ),
          IconButton(
            tooltip: context.tr('Sign out'),
            onPressed: () {
              widget.store.signOut();
              Navigator.of(context).pop();
            },
            icon: const Icon(HavenIcons.logout),
          ),
        ],
      ),
      drawer: showSidebar ? null : Drawer(child: _buildSidebar(context, true)),
      body: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                if (widget.agentStore.publishBlockedReason != null)
                  _PublishBlockedBanner(
                    reason: widget.agentStore.publishBlockedReason!,
                  ),
                _Breadcrumb(section: _activeNav),
                Expanded(child: _buildSectionBody()),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _section == _StaySection.accommodations
          ? FloatingActionButton.extended(
              onPressed: () => _showAddAccommodationDialog(context),
              icon: const Icon(HavenIcons.add),
              label: Text(context.tr('Add Accommodation')),
            )
          : null,
    );
  }

  Widget _buildSectionBody() {
    switch (_section) {
      case _StaySection.dashboard:
        return AgentDashboardOverview(
          agentStore: widget.agentStore,
          isRental: false,
          onAddProperty: () => _showAddAccommodationDialog(context),
          onOpenTab: (index) => setState(() {
            _section = switch (index) {
              0 => _StaySection.dashboard,
              1 => _StaySection.accommodations,
              2 => _StaySection.bookings,
              3 => _StaySection.messages,
              4 => _StaySection.reviews,
              5 => _StaySection.profile,
              6 => _StaySection.financial,
              _ => _StaySection.roomInventory,
            };
          }),
        );
      case _StaySection.accommodations:
        return _AccommodationsTab(
          store: widget.store,
          agentStore: widget.agentStore,
        );
      case _StaySection.bookings:
        return _BookingsTab(agentStore: widget.agentStore);
      case _StaySection.messages:
        return _MessagesTab(agentStore: widget.agentStore);
      case _StaySection.roomInventory:
        return RoomInventoryTab(
          agentStore: widget.agentStore,
          view: RoomInventoryView.categories,
        );
      case _StaySection.physicalRooms:
        return RoomInventoryTab(
          agentStore: widget.agentStore,
          view: RoomInventoryView.rooms,
        );
      case _StaySection.availability:
        return RoomInventoryTab(
          agentStore: widget.agentStore,
          view: RoomInventoryView.calendar,
        );
      case _StaySection.alerts:
        return NotificationCenterScreen(
          repository: NotificationRepository(
            tokenProvider: () =>
                widget.store.authenticationRepository.accessToken,
          ),
        );
      case _StaySection.reviews:
        return AgentReviewsTab(
          tokenProvider: () =>
              widget.store.authenticationRepository.accessToken,
        );
      case _StaySection.financial:
        return FinancialManagementScreen(
          view: FinancialView.overview,
          businessModel: PropertyBusinessModel.bookable,
          properties: widget.agentStore.myListings,
          tokenProvider: () =>
              widget.store.authenticationRepository.accessToken,
        );
      case _StaySection.utilities:
        return FinancialManagementScreen(
          view: FinancialView.expenses,
          businessModel: PropertyBusinessModel.bookable,
          properties: widget.agentStore.myListings,
          tokenProvider: () =>
              widget.store.authenticationRepository.accessToken,
        );
      case _StaySection.profile:
        return _ProfileTab(agentStore: widget.agentStore);
    }
  }

  Widget _buildSidebar(BuildContext context, bool closeOnSelect) {
    const groupLabels = _hotelGroupLabels;
    return Material(
      color: HavenTheme.white,
      child: SafeArea(
        child: ListView(
          key: const Key('portal-sidebar'),
          padding: const EdgeInsets.all(20),
          children: [
            PortalSidebarHeading(workspace: _portalTitle),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: FilledButton.icon(
                onPressed: () {
                  if (closeOnSelect) Navigator.of(context).pop();
                  _showAddAccommodationDialog(this.context);
                },
                icon: const Icon(HavenIcons.add),
                label: const Text('Add Hotel'),
              ),
            ),
            for (final group in _StayNavGroup.values) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                child: Text(
                  groupLabels[group]!,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              ..._navItems
                  .where((item) => item.group == group)
                  .map(
                    (item) => PortalSidebarItem(
                      icon: item.icon,
                      label: item.label,
                      selected: item.section == _section,
                      onTap: () {
                        setState(() => _section = item.section);
                        if (closeOnSelect) Navigator.of(context).pop();
                      },
                    ),
                  ),
            ],
            TextButton.icon(
              onPressed: () {
                if (closeOnSelect) Navigator.of(context).pop();
                Navigator.of(this.context).pop();
              },
              icon: const Icon(HavenIcons.chevronLeft, size: 16),
              label: Text(context.tr('Back to marketplace')),
            ),
          ],
        ),
      ),
    );
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  void _loadBookings() {
    widget.agentStore.loadBookings().catchError((Object error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });
  }

  void _showAddAccommodationDialog(BuildContext context) {
    if (!widget.agentStore.canPublish) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.agentStore.publishBlockedReason ?? 'Cannot publish listings',
          ),
        ),
      );
      return;
    }
    showListingEditorDialog(
      context: context,
      store: widget.store,
      businessModel: PropertyBusinessModel.bookable,
      categories: _categoriesFor(widget.agentStore),
      agentStore: widget.agentStore,
    );
  }
}

/// Category choices a workspace may create; keeps apartments and hotels apart.
List<PropertyCategory> _categoriesFor(AgentPortalStore store) =>
    store.isApartmentPortal
    ? const [
        PropertyCategory.shortStayApartment,
        PropertyCategory.servicedApartment,
      ]
    : const [
        PropertyCategory.hotel,
        PropertyCategory.lodge,
        PropertyCategory.motel,
      ];

class _UnauthorizedView extends StatelessWidget {
  const _UnauthorizedView({this.portalName = 'Hotel, Lodge & Motel'});

  final String portalName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Agent Portal'))),
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  HavenIcons.lockOutlined,
                  size: 48,
                  color: HavenTheme.muted,
                ),
                const SizedBox(height: 16),
                Text(
                  context.tr('Access Restricted'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${context.tr('You do not have permission to access the')} '
                  '$portalName ${context.tr('portal.')}',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PublishBlockedBanner extends StatelessWidget {
  const _PublishBlockedBanner({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.orange.shade100,
      child: Row(
        children: [
          const Icon(HavenIcons.warning, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Publishing restricted: $reason',
              style: const TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.section, this.portal = 'Hotel Agent'});

  final _StayNavItem section;
  final String portal;

  @override
  Widget build(BuildContext context) {
    final group =
        (section.group == _StayNavGroup.property && portal == 'Hotel Agent'
        ? _hotelGroupLabels
        : _apartmentGroupLabels)[section.group]!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Text(
        '$portal / $group / ${section.label}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _AccommodationsTab extends StatelessWidget {
  const _AccommodationsTab({
    required this.store,
    required this.agentStore,
    this.apartment = false,
  });

  final HavenLinkStore store;
  final AgentPortalStore agentStore;
  final bool apartment;

  @override
  Widget build(BuildContext context) {
    final listings = agentStore.myListings;

    if (listings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              apartment
                  ? HavenIcons.apartmentOutlined
                  : HavenIcons.hotelOutlined,
              size: 48,
              color: HavenTheme.muted,
            ),
            const SizedBox(height: 16),
            Text(
              context.tr(
                apartment ? 'No apartments yet' : 'No accommodations yet',
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                apartment
                    ? 'Register your first apartment to start hosting guests.'
                    : 'Create your first accommodation listing to get started.',
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: listings.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final property = listings[index];
        return _AccommodationCard(
          property: property,
          store: store,
          agentStore: agentStore,
        );
      },
    );
  }
}

class _AccommodationCard extends StatelessWidget {
  const _AccommodationCard({
    required this.property,
    required this.store,
    required this.agentStore,
  });

  final Property property;
  final HavenLinkStore store;
  final AgentPortalStore agentStore;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PropertyCard(property: property, store: store, onTap: () {}),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _StatusChip(status: property.listingStatus),
                const Spacer(),
                IconButton(
                  icon: const Icon(HavenIcons.visibilityOutlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PropertyDetailScreen(
                        property: property,
                        store: store,
                      ),
                    ),
                  ),
                  tooltip: context.tr('Preview as Customer'),
                ),
                IconButton(
                  icon: const Icon(HavenIcons.edit),
                  onPressed: () => showListingEditorDialog(
                    context: context,
                    store: store,
                    businessModel: PropertyBusinessModel.bookable,
                    categories: _categoriesFor(agentStore),
                    initial: property,
                  ),
                  tooltip: context.tr('Edit accommodation'),
                ),
                IconButton(
                  icon: const Icon(HavenIcons.delete),
                  onPressed: () => _showDeleteDialog(context, property),
                  tooltip: context.tr('Delete accommodation'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, Property property) {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Accommodation'),
        content: Text('Are you sure you want to delete "${property.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              navigator.pop();
              store.deleteListing(property.id).catchError((error) {
                messenger.showSnackBar(
                  SnackBar(content: Text(error.toString())),
                );
              });
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ListingStatus status;

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;

    switch (status) {
      case ListingStatus.published:
        color = Colors.green;
        icon = HavenIcons.checkCircle;
        break;
      case ListingStatus.pendingReview:
        color = Colors.orange;
        icon = HavenIcons.pending;
        break;
      case ListingStatus.paused:
        color = Colors.grey;
        icon = HavenIcons.pauseCircle;
        break;
      case ListingStatus.rejected:
        color = Colors.red;
        icon = HavenIcons.cancel;
        break;
      default:
        color = Colors.blue;
        icon = HavenIcons.drafts;
    }

    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(status.label),
      backgroundColor: color.withValues(alpha: 0.1),
    );
  }
}

class _BookingsTab extends StatelessWidget {
  const _BookingsTab({required this.agentStore, this.apartment = false});

  final AgentPortalStore agentStore;
  final bool apartment;

  @override
  Widget build(BuildContext context) {
    final bookings = agentStore.bookingsForMyListings;

    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(HavenIcons.luggageOutlined, size: 48, color: HavenTheme.muted),
            const SizedBox(height: 16),
            Text(
              'No bookings yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'When guests book your accommodations, bookings will appear here.',
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final booking = bookings[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(HavenIcons.hotel)),
            title: Text(booking.property.name),
            subtitle: Text(
              '${booking.guestName} · ${apartment ? 'Entire apartment · ${booking.guestCount} guests' : booking.roomTypeName ?? 'Room category pending'}'
              '${apartment || booking.assignedRoomNumber == null ? '' : ' · Room ${booking.assignedRoomNumber}'}\n'
              '${_date(booking.checkIn)} – ${_date(booking.checkOut)}\n'
              '${booking.id} · ${booking.status.name}',
            ),
            isThreeLine: true,
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  formatTzs(booking.totalTzs),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  booking.paymentTransactionId == null
                      ? 'Payment pending'
                      : 'Payment verified',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
            onTap: () => _showBookingDetails(context, booking),
          ),
        );
      },
    );
  }

  void _showBookingDetails(BuildContext context, Booking booking) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Booking: ${booking.property.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Guest: ${booking.guestName}'),
            if (booking.roomTypeName != null)
              Text('Room category: ${booking.roomTypeName}'),
            if (booking.assignedRoomNumber != null)
              Text('Assigned room: ${booking.assignedRoomNumber}'),
            const SizedBox(height: 8),
            Text('Check-in: ${_date(booking.checkIn)}'),
            const SizedBox(height: 4),
            Text('Check-out: ${_date(booking.checkOut)}'),
            const SizedBox(height: 8),
            Text('Total: ${formatTzs(booking.totalTzs)}'),
            const SizedBox(height: 8),
            Text('Status: ${booking.status.name}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (booking.status == BookingStatus.pending)
            FilledButton(
              onPressed: () =>
                  _updateBookingStatus(context, booking, BookingStatus.active),
              child: const Text('Confirm booking'),
            ),
          if (booking.status == BookingStatus.active)
            FilledButton(
              onPressed: () => _updateBookingStatus(
                context,
                booking,
                BookingStatus.completed,
              ),
              child: const Text('Mark completed'),
            ),
        ],
      ),
    );
  }

  Future<void> _updateBookingStatus(
    BuildContext context,
    Booking booking,
    BookingStatus status,
  ) async {
    try {
      await agentStore.updateBookingStatus(
        bookingId: booking.id,
        status: status,
      );
      if (!context.mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Booking marked ${status.name}.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _MessagesTab extends StatelessWidget {
  const _MessagesTab({required this.agentStore});

  final AgentPortalStore agentStore;

  @override
  Widget build(BuildContext context) {
    final bookings = agentStore.bookingsForMyListings;

    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              HavenIcons.chatBubbleOutline,
              size: 48,
              color: HavenTheme.muted,
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Guest messages will appear here once you have bookings.',
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final booking = bookings[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(HavenIcons.message)),
            title: Text(booking.guestName),
            subtitle: Text(
              '${booking.property.name} • ${_date(booking.checkIn)}',
            ),
            trailing: const Icon(HavenIcons.chevronRight),
            onTap: () => _showMessageThread(context, booking),
          ),
        );
      },
    );
  }

  void _showMessageThread(BuildContext context, Booking booking) {
    showDialog<void>(
      context: context,
      builder: (context) => _BookingMessagesDialog(
        store: agentStore.customerStore,
        booking: booking,
      ),
    );
  }
}

class _BookingMessagesDialog extends StatefulWidget {
  const _BookingMessagesDialog({required this.store, required this.booking});

  final HavenLinkStore store;
  final Booking booking;

  @override
  State<_BookingMessagesDialog> createState() => _BookingMessagesDialogState();
}

class _BookingMessagesDialogState extends State<_BookingMessagesDialog> {
  final _messageController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _messages;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _messages = widget.store.loadBookingMessages(widget.booking.id);
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Messages: ${widget.booking.guestName}'),
    content: SizedBox(
      width: 520,
      height: 420,
      child: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _messages,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          snapshot.error.toString(),
                          textAlign: TextAlign.center,
                        ),
                        TextButton(
                          onPressed: () => setState(
                            () => _messages = widget.store.loadBookingMessages(
                              widget.booking.id,
                            ),
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                final messages = snapshot.data ?? const [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('No messages in this conversation yet.'),
                  );
                }
                return ListView.separated(
                  itemCount: messages.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isAgent = message['senderType'] == 'agent';
                    return Align(
                      alignment: isAgent
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 380),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isAgent
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(message['body'] as String? ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Write a reply',
                    counterText: '',
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                tooltip: 'Send message',
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(HavenIcons.send),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );

  Future<void> _send() async {
    final body = _messageController.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.store.sendBookingMessage(
        bookingId: widget.booking.id,
        body: body,
      );
      if (!mounted) return;
      _messageController.clear();
      setState(() {
        _sending = false;
        _messages = widget.store.loadBookingMessages(widget.booking.id);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({required this.agentStore});

  final AgentPortalStore agentStore;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _agencyNameController;
  late final TextEditingController _bioController;
  late final TextEditingController _photoUrlController;
  late final TextEditingController _videoUrlController;
  bool _savingProfile = false;

  @override
  void initState() {
    super.initState();
    final agent = widget.agentStore.agent;
    _displayNameController = TextEditingController(text: agent?.fullName ?? '');
    _agencyNameController = TextEditingController(text: '');
    _bioController = TextEditingController(text: '');
    _photoUrlController = TextEditingController(text: '');
    _videoUrlController = TextEditingController(text: '');
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await widget.agentStore.loadProfile();
      if (!mounted) return;
      setState(() {
        _displayNameController.text = profile.displayName;
        _agencyNameController.text = profile.agencyName;
        _bioController.text = profile.bio;
        _photoUrlController.text = profile.photoUrl;
        _videoUrlController.text = profile.videoUrl;
      });
    } catch (error) {
      if (!mounted || !EnvConfig.backendConfigured) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _agencyNameController.dispose();
    _bioController.dispose();
    _photoUrlController.dispose();
    _videoUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agentStore.agent;
    if (agent == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final photoUrl = _photoUrlController.text.trim();
    final videoUrl = _videoUrlController.text.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (photoUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: Image.network(
                        photoUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            CircleAvatar(
                              radius: 40,
                              child: Text(agent.fullName[0].toUpperCase()),
                            ),
                      ),
                    )
                  else
                    CircleAvatar(
                      radius: 40,
                      child: Text(agent.fullName[0].toUpperCase()),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayNameController.text.isEmpty
                              ? agent.fullName
                              : _displayNameController.text,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(agent.email),
                        const SizedBox(height: 6),
                        Text(agent.phone),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              TextField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _agencyNameController,
                decoration: const InputDecoration(
                  labelText: 'Agency name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bioController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Bio / profile details',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _photoUrlController,
                decoration: const InputDecoration(
                  labelText: 'Photo upload URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _videoUrlController,
                decoration: const InputDecoration(
                  labelText: 'Video upload URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (photoUrl.isNotEmpty) ...[
                const Text(
                  'Photo preview',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    photoUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 180,
                      color: Colors.grey.shade200,
                      child: const Center(child: Text('Invalid photo URL')),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (videoUrl.isNotEmpty) ...[
                const Text(
                  'Video preview',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey.shade100,
                  ),
                  child: Row(
                    children: [
                      const Icon(HavenIcons.videocam, color: Colors.deepPurple),
                      const SizedBox(width: 12),
                      Expanded(child: Text(videoUrl)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              _ProfileRow(label: 'Role', value: agent.role.identifier),
              _ProfileRow(
                label: 'Verification',
                value: agent.verification.name,
              ),
              _ProfileRow(
                label: 'Account Status',
                value: agent.accountEnabled ? 'Active' : 'Suspended',
              ),
              if (agent.capabilities.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Capabilities:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: agent.capabilities
                      .map((cap) => Chip(label: Text(cap.name)))
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingProfile ? null : _saveProfile,
                  icon: _savingProfile
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(HavenIcons.saveAlt),
                  label: Text(
                    _savingProfile ? 'Saving profile' : 'Save profile details',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final agent = widget.agentStore.agent;
    if (agent == null) return;
    setState(() => _savingProfile = true);
    try {
      await widget.agentStore.saveProfile(
        AgentProfile(
          userId: agent.id,
          displayName: _displayNameController.text.trim(),
          agencyName: _agencyNameController.text.trim(),
          bio: _bioController.text.trim(),
          phone: agent.phone,
          email: agent.email,
          photoUrl: _photoUrlController.text.trim(),
          videoUrl: _videoUrlController.text.trim(),
          role: agent.role,
          capabilities: agent.capabilities,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            EnvConfig.backendConfigured
                ? 'Agent profile saved.'
                : 'Profile saved for this preview session.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';
