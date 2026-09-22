import 'package:flutter/material.dart';

import '../../../core/formatters/currency_formatter.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/domain/account_models.dart';
import '../../access/domain/access_control.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../properties/domain/property.dart';
import '../../properties/presentation/widgets/property_card.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    required this.store,
    required this.onOpenProperty,
    this.onOpenPortal,
    super.key,
  });

  final HavenLinkStore store;
  final ValueChanged<Property> onOpenProperty;
  final ValueChanged<Portal>? onOpenPortal;

  @override
  Widget build(BuildContext context) {
    if (!store.isSignedIn) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_circle_outlined,
                    color: HavenTheme.forest,
                    size: 46,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your Haven Link account',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Keep bookings, saved homes and unlocked owner contacts together.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => AuthScreen(store: store),
                      ),
                    ),
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in or create an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your account',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      store.customerEmail ?? 'Preview customer',
                      style: const TextStyle(color: HavenTheme.muted),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: store.signOut,
                icon: const Icon(Icons.logout, size: 17),
                label: const Text('Sign out'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AccountMetric(
                label: 'Bookings',
                value: store.bookings.length.toString(),
              ),
              _AccountMetric(
                label: 'Unlocked',
                value: store.unlockedProperties.length.toString(),
              ),
              _AccountMetric(
                label: 'Saved',
                value: store.savedPropertyIds.length.toString(),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'My bookings'),
              Tab(text: 'Unlocked properties'),
              Tab(text: 'Saved'),
              Tab(text: 'Recently viewed'),
              Tab(text: 'Payments'),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              children: [
                _BookingsTab(store: store, onOpenProperty: onOpenProperty),
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
                  emptyTitle: 'No saved properties yet',
                  emptyMessage: 'Save a listing to keep it close at hand.',
                ),
                _PropertyTab(
                  properties: store.recentlyViewed,
                  store: store,
                  onOpenProperty: onOpenProperty,
                  emptyTitle: 'Nothing viewed yet',
                  emptyMessage: 'Properties you open will appear here.',
                ),
                _PaymentsTab(store: store),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 4,
            children: [
              _AccountLink(icon: Icons.chat_bubble_outline, label: 'Messages'),
              _AccountLink(
                icon: Icons.notifications_none,
                label: 'Notifications',
              ),
              _AccountLink(icon: Icons.settings_outlined, label: 'Settings'),
              _AccountLink(icon: Icons.help_outline, label: 'Help & support'),
              if (store.currentUser?.role == AccountRole.rentalAgent ||
                  (store.currentUser?.hasCapability(
                        AgentCapability.rentalProperty,
                      ) ??
                      false))
                _AccountLink(
                  icon: Icons.home_work_outlined,
                  label: 'Rental Agent Portal',
                  onTap: () => onOpenPortal?.call(Portal.rentalAgent),
                ),
              if (store.currentUser?.role == AccountRole.stayAgent ||
                  (store.currentUser?.hasCapability(
                        AgentCapability.accommodationBooking,
                      ) ??
                      false))
                _AccountLink(
                  icon: Icons.hotel_outlined,
                  label: 'Stay Agent Portal',
                  onTap: () => onOpenPortal?.call(Portal.stayAgent),
                ),
              if (store.currentUser?.role == AccountRole.admin)
                _AccountLink(
                  icon: Icons.admin_panel_settings,
                  label: 'Admin Dashboard',
                  onTap: () => onOpenPortal?.call(Portal.admin),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BookingsTab extends StatelessWidget {
  const _BookingsTab({required this.store, required this.onOpenProperty});

  final HavenLinkStore store;
  final ValueChanged<Property> onOpenProperty;

  @override
  Widget build(BuildContext context) {
    if (store.bookings.isEmpty) {
      return const _EmptyTab(
        icon: Icons.luggage_outlined,
        title: 'No bookings yet',
        message:
            'Your confirmed hotels, lodges and apartments will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(top: 10),
      itemCount: store.bookings.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final booking = store.bookings[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.hotel_outlined)),
            title: Text(booking.property.name),
            subtitle: Text(
              '${booking.property.generalLocation}\n${_date(booking.checkIn)} – ${_date(booking.checkOut)}\n'
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
                const Text('Paid in preview', style: TextStyle(fontSize: 10)),
              ],
            ),
            onTap: () => onOpenProperty(booking.property),
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
      return const _EmptyTab(
        icon: Icons.key_outlined,
        title: 'No unlocked properties',
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
                  leading: const CircleAvatar(child: Icon(Icons.home_outlined)),
                  title: Text(unlocked.property.name),
                  subtitle: Text(
                    '${unlocked.property.generalLocation} · ${formatTzs(unlocked.property.priceTzs)}/month',
                  ),
                  trailing: IconButton(
                    tooltip: 'View property',
                    onPressed: () => onOpenProperty(unlocked.property),
                    icon: const Icon(Icons.arrow_forward),
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
        icon: Icons.home_outlined,
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
      return const _EmptyTab(
        icon: Icons.receipt_long_outlined,
        title: 'No payment history',
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
            leading: const Icon(Icons.receipt_long_outlined),
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
