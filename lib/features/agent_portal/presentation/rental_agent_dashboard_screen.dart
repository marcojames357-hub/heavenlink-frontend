import 'package:flutter/material.dart';

import '../../../core/formatters/currency_formatter.dart';
import '../../../core/state/haven_link_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../properties/domain/property.dart';
import '../../properties/presentation/widgets/property_card.dart';
import '../domain/agent_models.dart';
import 'listing_editor_dialog.dart';
import '../state/agent_portal_store.dart';

/// Dashboard for rental property agents.
///
/// Shows their listings, unlock activity, inquiries, and lets them
/// create/edit/remove properties.
class RentalAgentDashboardScreen extends StatefulWidget {
  const RentalAgentDashboardScreen({
    required this.store,
    required this.agentStore,
    super.key,
  });

  final HavenLinkStore store;
  final AgentPortalStore agentStore;

  @override
  State<RentalAgentDashboardScreen> createState() =>
      _RentalAgentDashboardScreenState();
}

class _RentalAgentDashboardScreenState
    extends State<RentalAgentDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    if (!widget.agentStore.isAuthorized) {
      return _UnauthorizedView();
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rental Agent Portal'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'My Listings'),
              Tab(text: 'Unlock Activity'),
              Tab(text: 'Inquiries'),
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
                  _ListingsTab(
                    store: widget.store,
                    agentStore: widget.agentStore,
                  ),
                  _UnlockActivityTab(agentStore: widget.agentStore),
                  _InquiriesTab(agentStore: widget.agentStore),
                  _ProfileTab(agentStore: widget.agentStore),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showAddPropertyDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('Add Property'),
        ),
      ),
    );
  }

  void _showAddPropertyDialog(BuildContext context) {
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
      businessModel: PropertyBusinessModel.contactUnlock,
    );
  }
}

class _UnauthorizedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rental Agent Portal')),
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
                  'You do not have permission to access the rental agent portal.',
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

class _ListingsTab extends StatelessWidget {
  const _ListingsTab({required this.store, required this.agentStore});

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
            Icon(Icons.home_work_outlined, size: 48, color: HavenTheme.muted),
            const SizedBox(height: 16),
            Text(
              'No listings yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create your first rental property listing to get started.',
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
        return _ListingCard(
          property: property,
          store: store,
          agentStore: agentStore,
        );
      },
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
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
                    businessModel: PropertyBusinessModel.contactUnlock,
                    initial: property,
                  ),
                  tooltip: 'Edit listing',
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _showDeleteDialog(context, property),
                  tooltip: 'Delete listing',
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
        title: const Text('Delete Listing'),
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

class _UnlockActivityTab extends StatelessWidget {
  const _UnlockActivityTab({required this.agentStore});

  final AgentPortalStore agentStore;

  @override
  Widget build(BuildContext context) {
    final activity = agentStore.unlockActivity;

    if (activity.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.key_outlined, size: 48, color: HavenTheme.muted),
            const SizedBox(height: 16),
            Text(
              'No unlock activity yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'When customers unlock your listings, activity will appear here.',
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: activity.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = activity[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.lock_open)),
            title: Text(item.listingName),
            subtitle: Text('Unlocked ${_date(item.record.createdAt)}'),
            trailing: Text(formatTzs(item.record.amountTzs ?? 0)),
          ),
        );
      },
    );
  }
}

class _InquiriesTab extends StatelessWidget {
  const _InquiriesTab({required this.agentStore});

  final AgentPortalStore agentStore;

  @override
  Widget build(BuildContext context) {
    final inquiries = agentStore.inquiries;

    if (inquiries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: HavenTheme.muted),
            const SizedBox(height: 16),
            Text(
              'No inquiries yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Customer questions about your listings will appear here.',
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: inquiries.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final inquiry = inquiries[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.question_answer)),
            title: Text(inquiry.customerName),
            subtitle: Text(inquiry.message),
            trailing: _InquiryStatusChip(status: inquiry.status),
            onTap: () => _showInquiryDialog(context, inquiry),
          ),
        );
      },
    );
  }

  void _showInquiryDialog(BuildContext context, ListingInquiry inquiry) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Inquiry from ${inquiry.customerName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(inquiry.message),
            const SizedBox(height: 16),
            if (inquiry.response != null) ...[
              const Text(
                'Your response:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(inquiry.response!),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (inquiry.status == InquiryStatus.open)
            TextButton(
              onPressed: () {
                // TODO: Show response form
                Navigator.pop(context);
              },
              child: const Text('Respond'),
            ),
        ],
      ),
    );
  }
}

class _InquiryStatusChip extends StatelessWidget {
  const _InquiryStatusChip({required this.status});

  final InquiryStatus status;

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case InquiryStatus.open:
        color = Colors.blue;
        break;
      case InquiryStatus.answered:
        color = Colors.green;
        break;
      case InquiryStatus.closed:
        color = Colors.grey;
        break;
    }

    return Chip(
      label: Text(status.name),
      backgroundColor: color.withOpacity(0.1),
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
