import 'package:flutter/material.dart';

import '../data/admin_users_repository.dart';
import '../../../core/formatters/currency_formatter.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../properties/domain/property.dart';

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
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Users'),
              Tab(text: 'Properties'),
              Tab(text: 'Bookings'),
              Tab(text: 'Payments'),
              Tab(text: 'Settings'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(store: widget.store),
            _UsersTab(store: widget.store),
            _PropertiesTab(store: widget.store),
            _BookingsTab(store: widget.store),
            _PaymentsTab(store: widget.store),
            _SettingsTab(store: widget.store),
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
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.admin_panel_settings,
                  size: 48,
                  color: HavenTheme.muted,
                ),
                const SizedBox(height: 16),
                Text(
                  'Access Restricted',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'You do not have permission to access the admin dashboard.',
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
  const _OverviewTab({required this.store});

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Platform Overview',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          _StatsGrid(store: store),
          const SizedBox(height: 24),
          _RecentActivitySection(store: store),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.store});

  final HavenLinkStore store;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _StatCard(
          title: 'Total Users',
          value: store.allProperties.length.toString(), // Placeholder
          icon: Icons.people,
          color: HavenTheme.teal,
        ),
        _StatCard(
          title: 'Properties',
          value: store.allProperties.length.toString(),
          icon: Icons.home_work,
          color: HavenTheme.mint,
        ),
        _StatCard(
          title: 'Bookings',
          value: store.bookings.length.toString(),
          icon: Icons.luggage,
          color: Colors.orange,
        ),
        _StatCard(
          title: 'Revenue',
          value: formatTzs(
            store.paymentRecords.fold<int>(
              0,
              (sum, record) => sum + record.amountTzs,
            ),
          ),
          icon: Icons.payments,
          color: Colors.green,
        ),
      ],
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
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: HavenTheme.muted),
            ),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
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
              'Recent Activity',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (store.notifications.isEmpty)
              const Text('No recent activity')
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
                    leading: const Icon(Icons.notifications),
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
                icon: const Icon(Icons.refresh),
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
      user.enabled ? Icons.person_outline : Icons.person_off_outlined,
    ),
    trailing: IconButton(
      tooltip: 'Manage account',
      onPressed: () => _editUser(user),
      icon: const Icon(Icons.manage_accounts_outlined),
    ),
  );

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
        leading: CircleAvatar(backgroundImage: NetworkImage(property.imageUrl)),
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
      backgroundColor: color.withOpacity(0.1),
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
        leading: const CircleAvatar(child: Icon(Icons.luggage)),
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

    return Row(
      children: [
        _PaymentStatChip(
          label: 'Total',
          value: formatTzs(total),
          color: HavenTheme.teal,
        ),
        const SizedBox(width: 8),
        _PaymentStatChip(
          label: 'Succeeded',
          value: succeeded.toString(),
          color: Colors.green,
        ),
        const SizedBox(width: 8),
        _PaymentStatChip(
          label: 'Failed',
          value: failed.toString(),
          color: Colors.red,
        ),
      ],
    );
  }
}

class _PaymentStatChip extends StatelessWidget {
  const _PaymentStatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        child: Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
      ),
      label: Text('$label: $value'),
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
        leading: const CircleAvatar(child: Icon(Icons.payment)),
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
              icon: const Icon(Icons.edit, size: 16),
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
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Require Listing Approval'),
              subtitle: const Text(
                'Listings must be approved before going public',
              ),
              value: true, // Placeholder
              onChanged: (value) {
                // TODO: Update setting
              },
            ),
            const Divider(),
            SwitchListTile(
              title: const Text('Enable Notifications'),
              subtitle: const Text('Send notifications for important events'),
              value: true, // Placeholder
              onChanged: (value) {
                // TODO: Update setting
              },
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
