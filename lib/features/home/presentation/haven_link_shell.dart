import 'dart:async';

import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/config/env_config.dart';
import '../../notifications/presentation/notification_center_screen.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../access/domain/access_control.dart';
import '../../account/domain/account_models.dart';
import '../../account/presentation/account_screen.dart';
import '../../agent_portal/presentation/accommodation_agent_dashboard_screen.dart';
import '../../agent_portal/presentation/rental_agent_dashboard_screen.dart';
import '../../agent_portal/state/agent_portal_store.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../home/presentation/home_screen.dart';
import '../../properties/domain/property.dart';
import '../../properties/presentation/property_detail_screen.dart';
import '../../properties/presentation/multi_room_stay_screen.dart';
import '../../search/presentation/property_browse_screen.dart';

class HavenLinkShell extends StatefulWidget {
  const HavenLinkShell({
    required this.store,
    required this.locale,
    required this.onLocaleChanged,
    super.key,
  });

  final HavenLinkStore store;
  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<HavenLinkShell> createState() => _HavenLinkShellState();
}

class _HavenLinkShellState extends State<HavenLinkShell> {
  int _selectedIndex = 0;
  int _unread = 0;
  String? _unreadFor;
  Timer? _unreadTimer;
  final _homeScroll = ScrollController();
  final _homeSections = <String, GlobalKey>{
    for (final name in ['discover', 'how', 'portals']) name: GlobalKey(),
  };

  late final NotificationRepository _notifications = NotificationRepository(
    tokenProvider: () => widget.store.authenticationRepository.accessToken,
  );

  bool get _showBell =>
      EnvConfig.backendConfigured && widget.store.currentUser != null;

  Future<void> _refreshUnread() async {
    if (!_showBell) {
      if (_unread != 0 && mounted) setState(() => _unread = 0);
      return;
    }
    try {
      final count = await _notifications.unreadCount();
      if (mounted && count != _unread) setState(() => _unread = count);
    } on StateError {
      // The bell is a convenience; a failed poll must not interrupt the user.
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationCenterScreen(repository: _notifications),
      ),
    );
    _refreshUnread();
  }

  late final Map<Portal, AgentPortalStore> _portalStores = {
    Portal.rentalAgent: AgentPortalStore(
      portal: Portal.rentalAgent,
      store: widget.store,
    ),
    Portal.apartmentAgent: AgentPortalStore(
      portal: Portal.apartmentAgent,
      store: widget.store,
    ),
    Portal.stayAgent: AgentPortalStore(
      portal: Portal.stayAgent,
      store: widget.store,
    ),
  };

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
    _unreadTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _refreshUnread(),
    );
    _refreshUnread();
  }

  @override
  void didUpdateWidget(covariant HavenLinkShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
    }
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
    _homeScroll.dispose();
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wideNavigation = MediaQuery.sizeOf(context).width >= 900;
    if (MediaQuery.sizeOf(context).width >= 1024 &&
        _selectedIndex == 3 &&
        widget.store.isSignedIn &&
        widget.store.currentUser?.role == AccountRole.customer) {
      return Scaffold(body: _selectedPage());
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        backgroundColor: HavenTheme.white,
        titleSpacing: 20,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: HavenTheme.forest,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                  bottomLeft: Radius.circular(5),
                ),
              ),
              child: const Icon(
                HavenIcons.homeRounded,
                size: 21,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text.rich(
                const TextSpan(text: 'Haven Link'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        actions: [
          if (wideNavigation) ...[
            if (MediaQuery.sizeOf(context).width >= 1440) ...[
              _homeAnchor(context, 'Discover', 'discover'),
              _homeAnchor(context, 'How it works', 'how'),
              _homeAnchor(context, 'For partners', 'portals'),
              _homeAnchor(context, 'Trust & safety', 'how'),
            ] else
              _headerDestination(context, 0, 'Explore'),
            _headerDestination(context, 1, 'Stays'),
            _headerDestination(context, 2, 'Rentals'),
            const SizedBox(width: 14),
          ],
          PopupMenuButton<Locale>(
            tooltip: context.tr('Change language'),
            icon: const Icon(HavenIcons.language),
            onSelected: widget.onLocaleChanged,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: const Locale('en'),
                child: Row(
                  children: [
                    const Expanded(child: Text('English')),
                    if (widget.locale.languageCode == 'en')
                      const Icon(HavenIcons.check, size: 18),
                  ],
                ),
              ),
              PopupMenuItem(
                value: const Locale('sw'),
                child: Row(
                  children: [
                    const Expanded(child: Text('Kiswahili')),
                    if (widget.locale.languageCode == 'sw')
                      const Icon(HavenIcons.check, size: 18),
                  ],
                ),
              ),
            ],
          ),
          if (_showBell)
            IconButton(
              tooltip: context.tr('Notifications'),
              onPressed: _openNotifications,
              icon: Badge(
                isLabelVisible: _unread > 0,
                label: Text(_unread > 99 ? '99+' : '$_unread'),
                child: const Icon(HavenIcons.notificationsNone),
              ),
            ),
          if (wideNavigation && widget.store.currentUser == null) ...[
            TextButton(
              onPressed: () => _openAuth(),
              child: Text(context.tr('Log in')),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 12),
              child: FilledButton(
                onPressed: () => _openAuth(register: true),
                child: Text(context.tr('Create account')),
              ),
            ),
          ] else
            IconButton(
              tooltip: context.tr(_isPortalUser ? 'Workspace' : 'Account'),
              onPressed: () {
                if (_isPortalUser) {
                  _enterWorkspace();
                } else {
                  _selectDestination(3);
                }
              },
              icon: Icon(
                _isPortalUser
                    ? HavenIcons.homeWorkOutlined
                    : HavenIcons.accountCircleOutlined,
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _selectedIndex == 0
          ? _selectedPage()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1320),
                child: SizedBox.expand(
                  child: Padding(
                    padding: _selectedIndex == 0
                        ? EdgeInsets.zero
                        : const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                    child: _selectedPage(),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: wideNavigation
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: _selectDestination,
              destinations: [
                NavigationDestination(
                  icon: Icon(HavenIcons.exploreOutlined),
                  label: context.tr('Explore'),
                ),
                NavigationDestination(
                  icon: Icon(HavenIcons.hotelOutlined),
                  label: context.tr('Stays'),
                ),
                NavigationDestination(
                  icon: Icon(HavenIcons.keyOutlined),
                  label: context.tr('Rentals'),
                ),
                NavigationDestination(
                  icon: Icon(HavenIcons.personOutline),
                  label: context.tr('Account'),
                ),
              ],
            ),
    );
  }

  Widget _homeAnchor(BuildContext context, String label, String section) =>
      TextButton(
        onPressed: () {
          setState(() => _selectedIndex = 0);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final target = _homeSections[section]?.currentContext;
            if (target != null) {
              Scrollable.ensureVisible(
                target,
                duration: const Duration(milliseconds: 300),
                alignment: .03,
              );
            }
          });
        },
        child: Text(context.tr(label)),
      );

  Widget _headerDestination(BuildContext context, int index, String label) {
    final selected = _selectedIndex == index;
    return TextButton(
      key: Key('nav-${label.toLowerCase()}'),
      onPressed: () => _selectDestination(index),
      style: TextButton.styleFrom(
        foregroundColor: selected ? HavenTheme.forest : HavenTheme.muted,
        textStyle: TextStyle(
          fontFamily: 'Inter',
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      child: Text(context.tr(label)),
    );
  }

  void _selectDestination(int index) {
    if (index == 3 && _isPortalUser) {
      _enterWorkspace();
    } else {
      setState(() => _selectedIndex = index);
    }
  }

  Future<void> _openAuth({bool register = false}) async {
    final user = await Navigator.of(context).push<User>(
      MaterialPageRoute<User>(
        builder: (_) =>
            AuthScreen(store: widget.store, initialRegister: register),
      ),
    );
    if (!mounted || user == null) return;
    if (_isPortalUser) {
      await _enterWorkspace();
    } else {
      setState(() => _selectedIndex = 3);
    }
  }

  Widget _selectedPage() => switch (_selectedIndex) {
    0 => HomeScreen(
      store: widget.store,
      onBrowse: _browse,
      onSearch: _searchFromHome,
      onSearchWithDates: (model, query, category, dates) =>
          _searchFromHome(model, query, category, dates),
      scrollController: _homeScroll,
      sectionKeys: _homeSections,
      onAccount: () =>
          widget.store.isSignedIn ? _selectDestination(3) : _openAuth(),
      onOpenProperty: _openProperty,
    ),
    1 => PropertyBrowseScreen(
      store: widget.store,
      businessModel: PropertyBusinessModel.bookable,
      onOpenProperty: _openProperty,
      onOpenStay: _openStay,
    ),
    2 => PropertyBrowseScreen(
      store: widget.store,
      businessModel: PropertyBusinessModel.contactUnlock,
      onOpenProperty: _openProperty,
    ),
    _ => AccountScreen(
      store: widget.store,
      onOpenProperty: _openProperty,
      onOpenPortal: _openPortal,
      onBackToMarketplace: () => setState(() => _selectedIndex = 0),
    ),
  };

  void _onStoreChanged() {
    if (!mounted) return;
    setState(() {});
    final userId = widget.store.currentUser?.id;
    if (userId != _unreadFor) {
      _unreadFor = userId;
      _refreshUnread();
    }
  }

  void _searchFromHome(
    PropertyBusinessModel model,
    String query,
    String? category, [
    DateTimeRange? dates,
  ]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(
              context.tr(
                model == PropertyBusinessModel.bookable ? 'Stays' : 'Rentals',
              ),
            ),
          ),
          body: PropertyBrowseScreen(
            store: widget.store,
            businessModel: model,
            initialQuery: query,
            initialCategory: category,
            onOpenProperty: (property) => _openProperty(property, dates),
            onOpenStay: (property, selectedDates, guests) =>
                _openStay(property, selectedDates ?? dates, guests),
          ),
        ),
      ),
    );
  }

  void _browse(PropertyBusinessModel model) {
    setState(
      () => _selectedIndex = model == PropertyBusinessModel.bookable ? 1 : 2,
    );
  }

  void _openPortal(Portal portal) {
    if (!AccessControl.canOpenPortal(widget.store.currentUser, portal)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This account cannot open that portal.')),
      );
      return;
    }
    setState(() => _selectedIndex = 0);
    final Widget page = switch (portal) {
      Portal.rentalAgent => RentalAgentDashboardScreen(
        store: widget.store,
        agentStore: _portalStores[portal]!,
      ),
      Portal.apartmentAgent => ApartmentAgentDashboardScreen(
        store: widget.store,
        agentStore: _portalStores[portal]!,
      ),
      Portal.stayAgent => StayAgentDashboardScreen(
        store: widget.store,
        agentStore: _portalStores[portal]!,
      ),
      Portal.admin => AdminDashboardScreen(store: widget.store),
    };
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (context) => page));
  }

  bool get _isPortalUser {
    final user = widget.store.currentUser;
    return user != null && user.role != AccountRole.customer;
  }

  /// Opens the agent's workspace, letting multi-workspace agents choose.
  Future<void> _enterWorkspace() async {
    final user = widget.store.currentUser;
    if (user == null) return;
    if (user.role == AccountRole.admin) {
      _openPortal(Portal.admin);
      return;
    }
    final options = AccessControl.allowedPortals(
      user,
    ).where((portal) => portal != Portal.admin).toList();
    if (options.isEmpty) {
      setState(() => _selectedIndex = 3);
      return;
    }
    if (options.length == 1) {
      _openPortal(options.single);
      return;
    }
    final choice = await showModalBottomSheet<Portal>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.tr('Switch workspace'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            for (final portal in options)
              ListTile(
                leading: Icon(_portalIcon(portal), color: HavenTheme.teal),
                title: Text(context.tr(portal.title)),
                onTap: () => Navigator.pop(context, portal),
              ),
          ],
        ),
      ),
    );
    if (choice != null && mounted) _openPortal(choice);
  }

  IconData _portalIcon(Portal portal) => switch (portal) {
    Portal.rentalAgent => HavenIcons.homeWorkOutlined,
    Portal.apartmentAgent => HavenIcons.apartmentOutlined,
    Portal.stayAgent => HavenIcons.hotelOutlined,
    Portal.admin => HavenIcons.adminPanelSettings,
  };

  void _openProperty(Property property, [DateTimeRange? dates]) {
    if (_isMultiRoomStay(property)) {
      _openStay(property, dates, 2);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PropertyDetailScreen(
          property: property,
          store: widget.store,
          initialDates: dates,
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.store.recordViewing(property.id);
    });
  }

  void _openStay(Property property, DateTimeRange? dates, int guests) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MultiRoomStayScreen(
          property: property,
          store: widget.store,
          initialDates: dates,
          initialGuestCount: guests,
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.store.recordViewing(property.id);
    });
  }

  bool _isMultiRoomStay(Property property) =>
      property.businessModel == PropertyBusinessModel.bookable &&
      const {
        PropertyCategory.hotel,
        PropertyCategory.motel,
        PropertyCategory.lodge,
      }.contains(property.category);
}
