import 'package:flutter/material.dart';

import '../../../core/formatters/currency_formatter.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../properties/domain/property.dart';
import '../../properties/presentation/widgets/property_card.dart';
import 'listing_editor_dialog.dart';
import '../state/agent_portal_store.dart';

/// Dashboard for stay agents managing hotels, lodges and apartments.
///
/// Shows their accommodations, bookings, room types, inventory, and
/// guest messages.
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
  @override
  Widget build(BuildContext context) {
    if (!widget.agentStore.isAuthorized) {
      return _UnauthorizedView();
    }

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Stay Agent Portal'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'My Accommodations'),
              Tab(text: 'Bookings'),
              Tab(text: 'Room Types'),
              Tab(text: 'Messages'),
              Tab(text: 'Profile'),
            ],
          ),
        ),
        body: Column(
          children: [
            if (widget.agentStore.publishBlockedReason != null)
              _PublishBlockedBanner(
                reason: widget.agentStore.publishBlockedReason!,
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _AccommodationsTab(
                    store: widget.store,
                    agentStore: widget.agentStore,
                  ),
                  _BookingsTab(agentStore: widget.agentStore),
                  _RoomTypesTab(agentStore: widget.agentStore),
                  _MessagesTab(agentStore: widget.agentStore),
                  _ProfileTab(agentStore: widget.agentStore),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddAccommodationDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('Add Accommodation'),
        ),
      ),
    );
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
    );
  }
}

class _UnauthorizedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stay Agent Portal')),
      body: Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outlined,
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
                  'You do not have permission to access the stay agent portal.',
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
          const Icon(Icons.warning, color: Colors.orange),
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

class _AccommodationsTab extends StatelessWidget {
  const _AccommodationsTab({required this.store, required this.agentStore});

  final HavenLinkStore store;
  final AgentPortalStore agentStore;

  @override
  Widget build(BuildContext context) {
    final listings = agentStore.myListings;

    if (listings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hotel_outlined, size: 48, color: HavenTheme.muted),
            const SizedBox(height: 16),
            Text(
              'No accommodations yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create your first accommodation listing to get started.',
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
                  icon: const Icon(Icons.edit),
                  onPressed: () => showListingEditorDialog(
                    context: context,
                    store: store,
                    businessModel: PropertyBusinessModel.bookable,
                    initial: property,
                  ),
                  tooltip: 'Edit accommodation',
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _showDeleteDialog(context, property),
                  tooltip: 'Delete accommodation',
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
        icon = Icons.check_circle;
        break;
      case ListingStatus.pendingReview:
        color = Colors.orange;
        icon = Icons.pending;
        break;
      case ListingStatus.paused:
        color = Colors.grey;
        icon = Icons.pause_circle;
        break;
      case ListingStatus.rejected:
        color = Colors.red;
        icon = Icons.cancel;
        break;
      default:
        color = Colors.blue;
        icon = Icons.drafts;
    }

    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(status.label),
      backgroundColor: color.withOpacity(0.1),
    );
  }
}

class _BookingsTab extends StatelessWidget {
  const _BookingsTab({required this.agentStore});

  final AgentPortalStore agentStore;

  @override
  Widget build(BuildContext context) {
    final bookings = agentStore.bookingsForMyListings;

    if (bookings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.luggage_outlined, size: 48, color: HavenTheme.muted),
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
            leading: const CircleAvatar(child: Icon(Icons.hotel)),
            title: Text(booking.property.name),
            subtitle: Text(
              '${booking.guestName}\n${_date(booking.checkIn)} – ${_date(booking.checkOut)}\n'
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
                Text(booking.status.name, style: const TextStyle(fontSize: 12)),
              ],
            ),
            onTap: () => _showBookingDetails(context, booking),
          ),
        );
      },
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
          if (booking.status.name == 'pending')
            TextButton(
              onPressed: () {
                // TODO: Confirm booking
                Navigator.pop(context);
              },
              child: const Text('Confirm'),
            ),
        ],
      ),
    );
  }
}

class _RoomTypesTab extends StatelessWidget {
  const _RoomTypesTab({required this.agentStore});

  final AgentPortalStore agentStore;

  @override
  Widget build(BuildContext context) {
    final listings = agentStore.myListings;

    if (listings.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bed_outlined, size: 48, color: HavenTheme.muted),
            const SizedBox(height: 16),
            Text(
              'No accommodations to manage',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Create accommodations first to add room types.'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: listings.length,
      itemBuilder: (context, index) {
        final property = listings[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            title: Text(property.name),
            subtitle: Text('Manage room types and inventory'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Room Types',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            // TODO: Add room type
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add Room Type'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Room type management coming soon'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Inventory',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            // TODO: Manage inventory
                          },
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: const Text('Manage Inventory'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Inventory management coming soon'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
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
            Icon(Icons.chat_bubble_outline, size: 48, color: HavenTheme.muted),
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
            leading: const CircleAvatar(child: Icon(Icons.message)),
            title: Text(booking.guestName),
            subtitle: Text(
              '${booking.property.name} • ${_date(booking.checkIn)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showMessageThread(context, booking),
          ),
        );
      },
    );
  }

  void _showMessageThread(BuildContext context, dynamic booking) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Messages: ${booking.guestName}'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Message thread coming soon'),
            SizedBox(height: 16),
            LinearProgressIndicator(),
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

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.agentStore});

  final AgentPortalStore agentStore;

  @override
  Widget build(BuildContext context) {
    final agent = agentStore.agent;
    if (agent == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 40,
                child: Text(agent.fullName[0].toUpperCase()),
              ),
              const SizedBox(height: 16),
              Text(
                agent.fullName,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(agent.email),
              const SizedBox(height: 8),
              Text(agent.phone),
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
            ],
          ),
        ),
      ),
    );
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
