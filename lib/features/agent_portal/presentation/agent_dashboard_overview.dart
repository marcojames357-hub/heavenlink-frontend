import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/formatters/currency_formatter.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/portal_page_header.dart';
import '../../../core/widgets/metric_card.dart';
import '../../../core/widgets/portfolio_operations.dart';
import '../domain/agent_models.dart';
import '../../properties/domain/property.dart' show Booking;
import '../state/agent_portal_store.dart';

class AgentDashboardOverview extends StatelessWidget {
  const AgentDashboardOverview({
    required this.agentStore,
    required this.onOpenTab,
    required this.isRental,
    this.onAddProperty,
    super.key,
  });

  final AgentPortalStore agentStore;
  final ValueChanged<int> onOpenTab;
  final bool isRental;
  final VoidCallback? onAddProperty;

  @override
  Widget build(BuildContext context) {
    final listings = agentStore.myListings;
    final bookings = agentStore.bookingsForMyListings;
    final unlocks = agentStore.unlockActivity;
    final userName = agentStore.agent?.fullName.trim().split(' ').first ?? '';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        PortalPageHeader(
          eyebrow: context.tr(
            isRental ? 'Rental Agent Portal' : 'Stay Agent Portal',
          ),
          title: userName.isEmpty
              ? 'Welcome back!'
              : 'Welcome back, $userName!',
          subtitle: isRental
              ? "Here's what's happening with your rental listings today."
              : "Here's what's happening with your properties today.",
          icon: isRental ? HavenIcons.keyOutlined : HavenIcons.hotelOutlined,
          action: onAddProperty == null
              ? null
              : FilledButton.icon(
                  onPressed: onAddProperty,
                  icon: const Icon(HavenIcons.add, size: 16),
                  label: Text(context.tr('Add property')),
                ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            final metrics = <_DashboardMetric>[
              _DashboardMetric(
                label: isRental ? 'Total listings' : 'Total properties',
                value: '${listings.length}',
                icon: isRental
                    ? HavenIcons.homeWorkOutlined
                    : HavenIcons.hotelOutlined,
                color: HavenTheme.forest,
              ),
              _DashboardMetric(
                label: 'Published',
                value: '${agentStore.publishedListings.length}',
                icon: HavenIcons.checkCircleOutline,
                color: Colors.green.shade700,
              ),
              _DashboardMetric(
                label: 'Pending approval',
                value: '${agentStore.pendingListings.length}',
                icon: HavenIcons.hourglassEmpty,
                color: Colors.orange.shade800,
              ),
              _DashboardMetric(
                label: isRental ? 'Contact unlocks' : 'Reservations',
                value: isRental ? '${unlocks.length}' : '${bookings.length}',
                icon: isRental
                    ? HavenIcons.keyOutlined
                    : HavenIcons.luggageOutlined,
                color: isRental ? Colors.deepPurple : Colors.blue.shade700,
              ),
            ];
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: metrics
                  .map(
                    (metric) => SizedBox(
                      width: width,
                      child: _MetricCard(metric: metric),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 20),
        PropertyPortfolioPanel(
          properties: listings,
          title: isRental ? 'Portfolio performance' : 'Property operations',
          onManage: () => onOpenTab(1),
          onActivity: () => onOpenTab(2),
        ),
        const SizedBox(height: 20),
        _ActivityCard(
          title: isRental ? 'Recent contact unlocks' : 'Upcoming reservations',
          actionLabel: isRental ? 'View unlocks' : 'View bookings',
          onAction: () => onOpenTab(2),
          child: isRental
              ? _UnlockActivity(unlocks: unlocks.take(4).toList())
              : _BookingActivity(bookings: bookings.take(4).toList()),
        ),
      ],
    );
  }
}

class _DashboardMetric {
  const _DashboardMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _DashboardMetric metric;

  @override
  Widget build(BuildContext context) => HavenMetricCard(
    label: metric.label,
    value: metric.value,
    icon: metric.icon,
    color: metric.color,
  );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.title,
    required this.actionLabel,
    required this.onAction,
    required this.child,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
          const Divider(height: 20),
          child,
        ],
      ),
    ),
  );
}

class _BookingActivity extends StatelessWidget {
  const _BookingActivity({required this.bookings});

  final List<Booking> bookings;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return const _EmptyActivity(message: 'No reservations yet.');
    }
    return Column(
      children: bookings
          .map(
            (booking) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                child: Icon(HavenIcons.hotelOutlined),
              ),
              title: Text(booking.guestName),
              subtitle: Text(
                '${booking.property.name} · ${_formatDate(booking.checkIn)}',
              ),
              trailing: Text(booking.status.name),
            ),
          )
          .toList(),
    );
  }
}

class _UnlockActivity extends StatelessWidget {
  const _UnlockActivity({required this.unlocks});

  final List<UnlockActivity> unlocks;

  @override
  Widget build(BuildContext context) {
    if (unlocks.isEmpty) {
      return const _EmptyActivity(message: 'No contact unlocks yet.');
    }
    return Column(
      children: unlocks
          .map(
            (unlock) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(HavenIcons.keyOutlined)),
              title: Text(unlock.listingName),
              subtitle: Text(_formatDate(unlock.record.createdAt)),
              trailing: Text(formatTzs(unlock.record.amountTzs ?? 0)),
            ),
          )
          .toList(),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
  );
}

String _formatDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
