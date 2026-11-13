import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/env_config.dart';
import '../data/admin_users_repository.dart';
import '../data/admin_dashboard_repository.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/portal_page_header.dart';
import '../../../core/widgets/metric_card.dart';
import '../../../core/widgets/portfolio_operations.dart';
import '../../notifications/presentation/notification_center_screen.dart';
import '../../../core/widgets/portal_sidebar.dart';
import '../../../core/widgets/portal_scaffold.dart';
import '../../properties/domain/property.dart';
import '../../properties/presentation/widgets/property_photo.dart';
import '../../reviews/presentation/admin_reviews_tab.dart';
import '../../reviews/presentation/admin_reports_tab.dart';
import '../../financial_management/presentation/admin_financial_overview_screen.dart';
import 'admin_room_inventory_screen.dart';
import 'admin_audit_events_tab.dart';

/// Administrator dashboard for Haven Link.
///
/// Provides tools to manage users, properties, bookings, payments,
/// configuration, and platform moderation.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({required this.store, super.key});

  final HavenLinkStore store;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final user = widget.store.currentUser;
    if (user == null || !user.isAdmin) {
      return _UnauthorizedView();
    }

    return DefaultTabController(
      length: 11,
      child: Builder(
        builder: (context) {
          final tabs = DefaultTabController.of(context);
          final showSidebar = MediaQuery.sizeOf(context).width >= 1100;
          final labels = [
            context.tr('Overview'),
            context.tr('Users'),
            context.tr('Properties'),
            context.tr('Bookings'),
            context.tr('Payments'),
            context.tr('Settings'),
            context.tr('Reviews'),
            context.tr('Problem reports'),
            context.tr('Financial Management'),
            context.tr('Room Inventory'),
            context.tr('Audit History'),
          ];
          const icons = [
            LucideIcons.layoutDashboard,
            LucideIcons.usersRound,
            LucideIcons.building2,
            LucideIcons.notebookPen,
            LucideIcons.wallet,
            LucideIcons.settings,
            LucideIcons.star,
            LucideIcons.circleAlert,
            LucideIcons.circleDollarSign,
            LucideIcons.doorOpen,
            LucideIcons.history,
          ];
          final pages = [
            _OverviewTab(
              store: widget.store,
              onReviewQueue: () => tabs.animateTo(2),
            ),
            _UsersTab(store: widget.store),
            _PropertiesTab(store: widget.store),
            _BookingsTab(store: widget.store),
            _PaymentsTab(store: widget.store),
            _SettingsTab(store: widget.store),
            AdminReviewsTab(
              tokenProvider: () =>
                  widget.store.authenticationRepository.accessToken,
            ),
            AdminReportsTab(
              tokenProvider: () =>
                  widget.store.authenticationRepository.accessToken,
            ),
            AdminFinancialOverviewScreen(
              tokenProvider: () =>
                  widget.store.authenticationRepository.accessToken,
            ),
            AdminRoomInventoryScreen(store: widget.store),
            AdminAuditEventsTab(
              tokenProvider: () =>
                  widget.store.authenticationRepository.accessToken,
            ),
          ];

          return AnimatedBuilder(
            animation: tabs,
            builder: (context, _) => HavenPortalScaffold(
              showSidebar: showSidebar,
              sidebar: _buildSidebar(context, tabs, labels, icons, false),
              appBar: AppBar(
                automaticallyImplyLeading: !showSidebar,
                title: showSidebar
                    ? PortalHeaderTitle(
                        title: labels[tabs.index],
                        destinations: labels,
                        onDestination: tabs.animateTo,
                      )
                    : Text(context.tr('Admin Dashboard')),
                actions: [
                  NotificationBellButton(
                    tokenProvider: () =>
                        widget.store.authenticationRepository.accessToken,
                  ),
                  PortalAvatar(name: widget.store.currentUser?.fullName ?? ''),
                  IconButton(
                    tooltip: context.tr('Sign out'),
                    onPressed: () {
                      widget.store.signOut();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(LucideIcons.logOut),
                  ),
                ],
                bottom: showSidebar
                    ? null
                    : TabBar(
                        isScrollable: true,
                        tabs: [for (final label in labels) Tab(text: label)],
                      ),
              ),
              drawer: showSidebar
                  ? null
                  : Drawer(
                      child: _buildSidebar(context, tabs, labels, icons, true),
                    ),
              body: Row(
                children: [Expanded(child: TabBarView(children: pages))],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    TabController tabs,
    List<String> labels,
    List<IconData> icons,
    bool closeOnSelect,
  ) {
    return Material(
      color: HavenTheme.white,
      child: SafeArea(
        child: ListView(
          key: const Key('portal-sidebar'),
          padding: const EdgeInsets.all(20),
          children: [
            PortalSidebarHeading(
              workspace: context.tr('Haven Link Administration'),
            ),
            for (var index = 0; index < labels.length; index++)
              PortalSidebarItem(
                icon: icons[index],
                label: labels[index],
                selected: tabs.index == index,
                onTap: () {
                  tabs.animateTo(index);
                  if (closeOnSelect) Navigator.of(context).pop();
                },
              ),
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
}

class _UnauthorizedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Admin Dashboard'))),
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  HavenIcons.adminPanelSettings,
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
                  context.tr(
                    'You do not have permission to access the admin dashboard.',
                  ),
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

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.store, this.onReviewQueue});
  final VoidCallback? onReviewQueue;

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PortalPageHeader(
            eyebrow: context.tr('Admin Dashboard'),
            action: FilledButton.icon(
              onPressed: onReviewQueue,
              icon: const Icon(HavenIcons.add, size: 16),
              label: Text(context.tr('Review queue')),
            ),
            title: context.tr('Platform Overview'),
            subtitle: context.tr('Monitor platform activity and operations.'),
            icon: HavenIcons.adminPanelSettingsOutlined,
          ),
          const SizedBox(height: 16),
          _StatsGrid(store: store),
          const SizedBox(height: 24),
          PropertyPortfolioPanel(
            properties: store.allProperties,
            title: 'Live operations',
            onManage: onReviewQueue,
          ),
          const SizedBox(height: 20),
          _RecentActivitySection(store: store),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatefulWidget {
  const _StatsGrid({required this.store});

  final HavenLinkStore store;

  @override
  State<_StatsGrid> createState() => _StatsGridState();
}

class _StatsGridState extends State<_StatsGrid> {
  late final AdminDashboardRepository _repository = AdminDashboardRepository(
    tokenProvider: () => widget.store.authenticationRepository.accessToken,
  );
  Future<AdminDashboardSummary>? _summary;

  @override
  void initState() {
    super.initState();
    if (EnvConfig.backendConfigured) _summary = _repository.loadSummary();
  }

  void _reload() {
    setState(() => _summary = _repository.loadSummary());
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (summary == null) {
      return Column(
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Connect the backend for live admin metrics. Other values are local preview data.',
              ),
            ),
          ),
          _statsGrid(
            totalUsers: '—',
            totalProperties: widget.store.allProperties.length.toString(),
            totalBookings: widget.store.bookings.length.toString(),
            totalRevenue: formatTzs(
              widget.store.paymentRecords.fold<int>(
                0,
                (sum, record) => sum + record.amountTzs,
              ),
            ),
          ),
        ],
      );
    }

    return FutureBuilder<AdminDashboardSummary>(
      future: summary,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(snapshot.error.toString()),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _reload,
                      icon: const Icon(HavenIcons.refresh),
                      label: const Text('Retry'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final stats = snapshot.requireData;
        return _statsGrid(
          totalUsers: stats.totalUsers.toString(),
          totalProperties: stats.totalProperties.toString(),
          totalBookings: stats.totalBookings.toString(),
          totalRevenue: formatTzs(stats.totalRevenueTzs),
        );
      },
    );
  }

  Widget _statsGrid({
    required String totalUsers,
    required String totalProperties,
    required String totalBookings,
    required String totalRevenue,
  }) {
    final cards = <Widget>[
      _StatCard(
        title: context.tr('Total Users'),
        value: totalUsers,
        icon: HavenIcons.people,
        color: HavenTheme.teal,
      ),
      _StatCard(
        title: context.tr('Properties'),
        value: totalProperties,
        icon: HavenIcons.homeWork,
        color: HavenTheme.mint,
      ),
      _StatCard(
        title: context.tr('Bookings'),
        value: totalBookings,
        icon: HavenIcons.luggage,
        color: Colors.orange,
      ),
      _StatCard(
        title: context.tr('Revenue'),
        value: totalRevenue,
        icon: HavenIcons.payments,
        color: Colors.green,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      HavenMetricCard(label: title, value: value, icon: icon, color: color);
}

class _RecentActivitySection extends StatelessWidget {
  const _RecentActivitySection({required this.store});

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Recent Activity'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (store.notifications.isEmpty)
              Text(context.tr('No recent activity'))
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: store.notifications.take(5).length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final notification = store.notifications[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(HavenIcons.notifications),
                    title: Text(notification.title),
                    subtitle: Text(notification.message),
                    trailing: Text(
                      _formatTime(notification.createdAt),
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab({required this.store});

  final HavenLinkStore store;

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  late final _repository = AdminUsersRepository(
    tokenProvider: () => widget.store.authenticationRepository.accessToken,
  );
  List<AdminUserRecord> _users = const [];
  String _roleFilter = '';
  String _statusFilter = '';
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await _repository.loadUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = _users
        .where((user) {
          final roleMatches = _roleFilter.isEmpty || user.role == _roleFilter;
          final statusMatches =
              _statusFilter.isEmpty ||
              (_statusFilter == 'enabled' && user.enabled) ||
              (_statusFilter == 'suspended' && !user.enabled) ||
              (_statusFilter == user.verification);
          return roleMatches && statusMatches;
        })
        .toList(growable: false);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'User Management',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh users',
                onPressed: _loading ? null : _load,
                icon: const Icon(HavenIcons.refresh),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _roleFilter,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All roles')),
                    DropdownMenuItem(
                      value: 'CUSTOMER',
                      child: Text('Customer'),
                    ),
                    DropdownMenuItem(
                      value: 'RENTAL_AGENT',
                      child: Text('Rental Agent'),
                    ),
                    DropdownMenuItem(
                      value: 'STAY_AGENT',
                      child: Text('Stay Agent'),
                    ),
                    DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
                  ],
                  onChanged: (value) =>
                      setState(() => _roleFilter = value ?? ''),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _statusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Account status',
                  ),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All statuses')),
                    DropdownMenuItem(value: 'enabled', child: Text('Enabled')),
                    DropdownMenuItem(
                      value: 'suspended',
                      child: Text('Suspended'),
                    ),
                    DropdownMenuItem(
                      value: 'verified',
                      child: Text('Phone verified'),
                    ),
                    DropdownMenuItem(
                      value: 'unverified',
                      child: Text('Unverified phone'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _statusFilter = value ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : users.isEmpty
                ? const Center(child: Text('No matching accounts'))
                : ListView.separated(
                    itemCount: users.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) => _userTile(users[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _userTile(AdminUserRecord user) => ListTile(
    title: Text(user.fullName),
    subtitle: Text(
      '${user.email} · ${user.phone} · ${user.role} · ${user.verification}',
    ),
    leading: Icon(
      user.enabled ? HavenIcons.personOutline : HavenIcons.personOffOutlined,
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (user.role == 'RENTAL_AGENT' || user.role == 'STAY_AGENT')
          IconButton(
            tooltip: 'Agent workspaces',
            onPressed: () => _manageWorkspaces(user),
            icon: const Icon(HavenIcons.workspacesOutline),
          ),
        IconButton(
          tooltip: 'Manage account',
          onPressed: () => _editUser(user),
          icon: const Icon(HavenIcons.manageAccountsOutlined),
        ),
      ],
    ),
  );

  Future<void> _manageWorkspaces(AdminUserRecord user) async {
    Map<String, String> statuses;
    try {
      statuses = await _repository.loadWorkspaces(user.id);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    }
    if (!mounted) return;
    const titles = {
      'RENTAL': 'Long-Term Rentals',
      'APARTMENT': 'Apartments / Short-Term Stays',
      'HOTEL': 'Hotels, Lodges & Motels',
    };
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('${user.fullName} · workspaces'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in titles.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  subtitle: Text(statuses[entry.key] ?? 'not granted'),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Change workspace access',
                    onSelected: (status) async {
                      try {
                        await _repository.setWorkspaceStatus(
                          user.id,
                          entry.key,
                          status,
                        );
                        statuses = await _repository.loadWorkspaces(user.id);
                        setDialogState(() {});
                      } catch (error) {
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'active', child: Text('Activate')),
                      PopupMenuItem(
                        value: 'pending_review',
                        child: Text('Mark pending review'),
                      ),
                      PopupMenuItem(value: 'revoked', child: Text('Revoke')),
                    ],
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editUser(AdminUserRecord user) async {
    var role = user.role;
    var enabled = user.enabled;
    final capabilities = Set<String>.of(user.capabilities);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(user.fullName),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Account role'),
                  items: const [
                    DropdownMenuItem(
                      value: 'CUSTOMER',
                      child: Text('Customer'),
                    ),
                    DropdownMenuItem(
                      value: 'RENTAL_AGENT',
                      child: Text('Rental Agent'),
                    ),
                    DropdownMenuItem(
                      value: 'STAY_AGENT',
                      child: Text('Stay Agent'),
                    ),
                    DropdownMenuItem(value: 'ADMIN', child: Text('Admin')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => role = value ?? role),
                ),
                if (role == 'RENTAL_AGENT' || role == 'STAY_AGENT') ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Rental listings'),
                    value:
                        capabilities.contains('rentalProperty') ||
                        role == 'RENTAL_AGENT',
                    onChanged: (value) => setDialogState(() {
                      value == true
                          ? capabilities.add('rentalProperty')
                          : capabilities.remove('rentalProperty');
                    }),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Stay bookings'),
                    value:
                        capabilities.contains('accommodationBooking') ||
                        role == 'STAY_AGENT',
                    onChanged: (value) => setDialogState(() {
                      value == true
                          ? capabilities.add('accommodationBooking')
                          : capabilities.remove('accommodationBooking');
                    }),
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Account enabled'),
                  value: enabled,
                  onChanged: (value) => setDialogState(() => enabled = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    if (role == 'RENTAL_AGENT') capabilities.add('rentalProperty');
    if (role == 'STAY_AGENT') capabilities.add('accommodationBooking');
    if (role == 'CUSTOMER' || role == 'ADMIN') capabilities.clear();
    try {
      await _repository.updateUser(
        user,
        role: role,
        capabilities: capabilities,
        enabled: enabled,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _PropertiesTab extends StatelessWidget {
  const _PropertiesTab({required this.store});

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Property Management',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PropertyStats(store: store),
          const SizedBox(height: 16),
          _PropertyList(store: store),
        ],
      ),
    );
  }
}

class _PropertyStats extends StatelessWidget {
  const _PropertyStats({required this.store});

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    final total = store.allProperties.length;
    final published = store.allProperties.where((p) => p.isPublic).length;
    final pending = store.allProperties
        .where((p) => p.listingStatus == ListingStatus.pendingReview)
        .length;

    return Row(
      children: [
        _PropertyStatChip(label: 'Total', value: total, color: HavenTheme.teal),
        const SizedBox(width: 8),
        _PropertyStatChip(
          label: 'Published',
          value: published,
          color: Colors.green,
        ),
        const SizedBox(width: 8),
        _PropertyStatChip(
          label: 'Pending',
          value: pending,
          color: Colors.orange,
        ),
      ],
    );
  }
}

class _PropertyStatChip extends StatelessWidget {
  const _PropertyStatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        child: Text(
          value.toString(),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      label: Text(label),
    );
  }
}

class _PropertyList extends StatelessWidget {
  const _PropertyList({required this.store});

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    final properties = store.allProperties;

    if (properties.isEmpty) {
      return const Center(child: Text('No properties yet'));
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: properties.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final property = properties[index];
        return _PropertyListItem(store: store, property: property);
      },
    );
  }
}

class _PropertyListItem extends StatelessWidget {
  const _PropertyListItem({required this.store, required this.property});

  final HavenLinkStore store;
  final Property property;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 48,
            height: 48,
            child: PropertyPhoto(imageUrl: property.imageUrl, height: 48),
          ),
        ),
        title: Text(property.name),
        subtitle: Text(
          '${property.generalLocation} • ${property.businessModel.name}',
        ),
        trailing: _StatusChip(status: property.listingStatus),
        onTap: () => _showPropertyDetails(context, property),
      ),
    );
  }

  void _showPropertyDetails(BuildContext context, Property property) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(property.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Location: ${property.generalLocation}'),
              const SizedBox(height: 8),
              Text(
                'Price: ${formatTzs(property.priceTzs)}${property.pricePeriod}',
              ),
              const SizedBox(height: 8),
              Text('Status: ${property.listingStatus.label}'),
              const SizedBox(height: 8),
              Text('Category: ${property.category.name}'),
              const SizedBox(height: 8),
              Text('Agent ID: ${property.agentId}'),
              const SizedBox(height: 16),
              Text('Description: ${property.description}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (property.listingStatus == ListingStatus.pendingReview)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _updateStatus(context, ListingStatus.published);
              },
              child: const Text('Approve'),
            ),
          if (property.listingStatus == ListingStatus.pendingReview)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _updateStatus(context, ListingStatus.rejected);
              },
              child: const Text('Reject'),
            ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(BuildContext context, ListingStatus status) async {
    try {
      await store.setListingStatus(property.id, status);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ListingStatus status;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case ListingStatus.published:
        color = Colors.green;
        break;
      case ListingStatus.pendingReview:
        color = Colors.orange;
        break;
      case ListingStatus.paused:
        color = Colors.grey;
        break;
      case ListingStatus.rejected:
        color = Colors.red;
        break;
      default:
        color = Colors.blue;
    }

    return Chip(
      label: Text(status.label),
      backgroundColor: color.withValues(alpha: 0.1),
    );
  }
}

class _BookingsTab extends StatelessWidget {
  const _BookingsTab({required this.store});

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Booking Management',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          if (store.bookings.isEmpty)
            const Center(child: Text('No bookings yet'))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: store.bookings.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final booking = store.bookings[index];
                return _BookingListItem(booking: booking);
              },
            ),
        ],
      ),
    );
  }
}

class _BookingListItem extends StatelessWidget {
  const _BookingListItem({required this.booking});

  final dynamic booking;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(HavenIcons.luggage)),
        title: Text(booking.property.name),
        subtitle: Text('${booking.guestName} • ${_date(booking.checkIn)}'),
        trailing: Text(formatTzs(booking.totalTzs)),
        onTap: () => _showBookingDetails(context, booking),
      ),
    );
  }

  void _showBookingDetails(BuildContext context, dynamic booking) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Booking: ${booking.property.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Guest: ${booking.guestName}'),
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
        ],
      ),
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({required this.store});

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment Management',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          _PaymentStats(store: store),
          const SizedBox(height: 16),
          if (store.paymentRecords.isEmpty)
            const Center(child: Text('No payment records yet'))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: store.paymentRecords.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final payment = store.paymentRecords[index];
                return _PaymentListItem(payment: payment);
              },
            ),
        ],
      ),
    );
  }
}

class _PaymentStats extends StatelessWidget {
  const _PaymentStats({required this.store});

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    final total = store.paymentRecords.fold<int>(
      0,
      (sum, p) => sum + p.amountTzs,
    );
    final succeeded = store.paymentRecords
        .where((p) => p.status?.name == 'succeeded')
        .length;
    final failed = store.paymentRecords
        .where((p) => p.status?.name == 'failed')
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 780
            ? 3
            : constraints.maxWidth >= 500
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, value, icon, color) in [
              ('Total', formatTzs(total), HavenIcons.payments, HavenTheme.teal),
              (
                'Succeeded',
                succeeded.toString(),
                HavenIcons.checkCircle,
                Colors.green,
              ),
              ('Failed', failed.toString(), HavenIcons.cancel, Colors.red),
            ])
              SizedBox(
                width: width,
                child: HavenMetricCard(
                  label: label,
                  value: value,
                  icon: icon,
                  color: color,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PaymentListItem extends StatelessWidget {
  const _PaymentListItem({required this.payment});

  final dynamic payment;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(HavenIcons.payment)),
        title: Text(payment.purpose),
        subtitle: Text('${payment.property.name} • ${payment.method}'),
        trailing: Text(formatTzs(payment.amountTzs)),
        onTap: () => _showPaymentDetails(context, payment),
      ),
    );
  }

  void _showPaymentDetails(BuildContext context, dynamic payment) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Payment: ${payment.reference}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Purpose: ${payment.purpose}'),
            const SizedBox(height: 8),
            Text('Amount: ${formatTzs(payment.amountTzs)}'),
            const SizedBox(height: 8),
            Text('Method: ${payment.method}'),
            const SizedBox(height: 8),
            Text('Status: ${payment.status?.name ?? 'Unknown'}'),
            const SizedBox(height: 8),
            Text('Date: ${_date(payment.createdAt)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.store});

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Platform Settings',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          _FeeSettingsCard(store: store),
          const SizedBox(height: 16),
          _PlatformSettingsCard(),
        ],
      ),
    );
  }
}

class _FeeSettingsCard extends StatelessWidget {
  const _FeeSettingsCard({required this.store});

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fee Configuration',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _FeeRow(
              label: 'Contact Unlock Fee',
              value: formatTzs(store.feeSettings.unlockFeeTzs),
              onEdit: () => _editUnlockFee(context),
            ),
            const SizedBox(height: 12),
            _FeeRow(
              label: 'Booking Fee Rate',
              value:
                  '${(store.feeSettings.bookingFeeRate * 100).toStringAsFixed(1)}%',
              onEdit: () => _editBookingFee(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editUnlockFee(BuildContext context) async {
    final controller = TextEditingController(
      text: store.feeSettings.unlockFeeTzs.toString(),
    );
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Contact unlock fee'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount in TZS'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, int.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      await store.updateBusinessConfiguration(unlockFeeTzs: value);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _editBookingFee(BuildContext context) async {
    final controller = TextEditingController(
      text: (store.feeSettings.bookingFeeRate * 100).toStringAsFixed(1),
    );
    final value = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Booking service fee'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Percentage'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, double.tryParse(controller.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      await store.updateBusinessConfiguration(bookingFeeRate: value / 100);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({
    required this.label,
    required this.value,
    required this.onEdit,
  });

  final String label;
  final String value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Row(
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(HavenIcons.edit, size: 16),
              onPressed: onEdit,
            ),
          ],
        ),
      ],
    );
  }
}

class _PlatformSettingsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Platform Settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(HavenIcons.verifiedOutlined),
              title: Text('Listing approval'),
              subtitle: Text(
                'New listings are submitted for review and are only public once published.',
              ),
            ),
            const Divider(),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(HavenIcons.notificationsActiveOutlined),
              title: Text('Notifications'),
              subtitle: Text(
                'Booking, payment, checkout and rent alerts are always sent in-app. Customers and agents choose their own channels in notification preferences.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime value) => '${value.day}/${value.month}/${value.year}';

String _formatTime(DateTime value) {
  final now = DateTime.now();
  final difference = now.difference(value);

  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return _date(value);
}
