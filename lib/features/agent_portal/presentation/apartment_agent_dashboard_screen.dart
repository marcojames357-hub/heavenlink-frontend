part of 'accommodation_agent_dashboard_screen.dart';

const List<_StayNavItem> _apartmentNavItems = [
  _StayNavItem(
    _StaySection.dashboard,
    'Dashboard',
    HavenIcons.dashboardOutlined,
    _StayNavGroup.main,
  ),
  _StayNavItem(
    _StaySection.accommodations,
    'My Apartments',
    HavenIcons.apartmentOutlined,
    _StayNavGroup.main,
  ),
  _StayNavItem(
    _StaySection.bookings,
    'Reservations',
    HavenIcons.luggageOutlined,
    _StayNavGroup.property,
  ),
  _StayNavItem(
    _StaySection.availability,
    'Availability Calendar',
    HavenIcons.eventAvailableOutlined,
    _StayNavGroup.property,
  ),
  _StayNavItem(
    _StaySection.financial,
    'Financial Overview',
    HavenIcons.paymentsOutlined,
    _StayNavGroup.business,
  ),
  _StayNavItem(
    _StaySection.utilities,
    'Utilities & Expenses',
    HavenIcons.receiptLongOutlined,
    _StayNavGroup.business,
  ),
  _StayNavItem(
    _StaySection.messages,
    'Messages',
    HavenIcons.chatBubbleOutline,
    _StayNavGroup.communication,
  ),
  _StayNavItem(
    _StaySection.reviews,
    'Reviews & Ratings',
    HavenIcons.reviewsOutlined,
    _StayNavGroup.communication,
  ),
  _StayNavItem(
    _StaySection.alerts,
    'Alerts',
    HavenIcons.notificationsOutlined,
    _StayNavGroup.communication,
  ),
  _StayNavItem(
    _StaySection.profile,
    'Settings',
    HavenIcons.manageAccountsOutlined,
    _StayNavGroup.account,
  ),
];

/// Airbnb-style host portal for furnished apartments booked as whole units.
///
/// It has no room categories, room IDs or walk-in reservations.
class ApartmentAgentDashboardScreen extends StatefulWidget {
  const ApartmentAgentDashboardScreen({
    required this.store,
    required this.agentStore,
    super.key,
  });

  final HavenLinkStore store;
  final AgentPortalStore agentStore;

  @override
  State<ApartmentAgentDashboardScreen> createState() =>
      _ApartmentAgentDashboardScreenState();
}

class _ApartmentAgentDashboardScreenState
    extends State<ApartmentAgentDashboardScreen> {
  _StaySection _section = _StaySection.dashboard;

  _StayNavItem get _activeNav =>
      _apartmentNavItems.firstWhere((item) => item.section == _section);

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onDataChanged);
    widget.agentStore.addListener(_onDataChanged);
    _loadBookings();
  }

  @override
  void didUpdateWidget(covariant ApartmentAgentDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onDataChanged);
      widget.store.addListener(_onDataChanged);
    }
    if (oldWidget.agentStore != widget.agentStore) {
      oldWidget.agentStore.removeListener(_onDataChanged);
      widget.agentStore.addListener(_onDataChanged);
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
      return _UnauthorizedView(portalName: 'Apartment Stays');
    }

    final showSidebar = MediaQuery.of(context).size.width >= 980;
    return HavenPortalScaffold(
      showSidebar: showSidebar,
      sidebar: _buildSidebar(context, false),
      appBar: AppBar(
        automaticallyImplyLeading: !showSidebar,
        title: showSidebar
            ? PortalHeaderTitle(
                title: _activeNav.label,
                destinations: _apartmentNavItems.map((e) => e.label).toList(),
                onDestination: (index) => setState(
                  () => _section = _apartmentNavItems[index].section,
                ),
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
                _Breadcrumb(section: _activeNav, portal: 'Apartment Agent'),
                Expanded(child: _buildSectionBody()),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _section == _StaySection.accommodations
          ? FloatingActionButton.extended(
              onPressed: () => _showAddApartmentDialog(context),
              icon: const Icon(HavenIcons.add),
              label: Text(context.tr('Add Apartment')),
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
          onAddProperty: () => _showAddApartmentDialog(context),
          onOpenTab: (index) => setState(() {
            _section = switch (index) {
              0 => _StaySection.dashboard,
              1 => _StaySection.accommodations,
              2 => _StaySection.bookings,
              3 => _StaySection.messages,
              4 => _StaySection.reviews,
              5 => _StaySection.profile,
              6 => _StaySection.financial,
              _ => _StaySection.availability,
            };
          }),
        );
      case _StaySection.accommodations:
        return _AccommodationsTab(
          store: widget.store,
          agentStore: widget.agentStore,
          apartment: true,
        );
      case _StaySection.bookings:
        return _BookingsTab(agentStore: widget.agentStore, apartment: true);
      case _StaySection.messages:
        return _MessagesTab(agentStore: widget.agentStore);
      case _StaySection.availability:
        return ApartmentAvailabilityTab(
          listings: widget.agentStore.myListings,
          tokenProvider: () =>
              widget.store.authenticationRepository.accessToken,
        );
      case _StaySection.roomInventory:
      case _StaySection.physicalRooms:
        return const SizedBox.shrink();
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
    const groupLabels = _apartmentGroupLabels;
    return Material(
      color: HavenTheme.white,
      child: SafeArea(
        child: ListView(
          key: const Key('portal-sidebar'),
          padding: const EdgeInsets.all(20),
          children: [
            const PortalSidebarHeading(workspace: 'Apartment Stays Portal'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: FilledButton.icon(
                onPressed: () {
                  if (closeOnSelect) Navigator.of(context).pop();
                  _showAddApartmentDialog(this.context);
                },
                icon: const Icon(HavenIcons.add),
                label: const Text('Add Apartment'),
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
              ..._apartmentNavItems
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

  void _showAddApartmentDialog(BuildContext context) {
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
      categories: const [
        PropertyCategory.shortStayApartment,
        PropertyCategory.servicedApartment,
      ],
    );
  }
}
