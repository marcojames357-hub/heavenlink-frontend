import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../data/review_repository.dart';
import '../domain/review_models.dart';
import 'review_flow_screen.dart';
import 'widgets/attachment_picker.dart';
import 'widgets/guest_review_card.dart';

/// Customer "My trips": Upcoming / Ongoing / Completed stays, plus reports.
class CustomerReviewsTab extends StatefulWidget {
  const CustomerReviewsTab({
    required this.tokenProvider,
    this.repository,
    this.picker = pickUploads,
    super.key,
  });

  final String? Function() tokenProvider;
  final ReviewRepository? repository;
  final UploadPicker picker;

  @override
  State<CustomerReviewsTab> createState() => _CustomerReviewsTabState();
}

class _CustomerReviewsTabState extends State<CustomerReviewsTab> {
  late final ReviewRepository _repository;
  late Future<List<TripBooking>> _trips;
  late Future<List<ProblemReportItem>> _reports;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        ReviewRepository(tokenProvider: widget.tokenProvider);
    _reload();
  }

  void _reload() {
    _trips = _repository.loadTrips();
    _reports = _repository.loadMyReports();
  }

  Future<void> _open(TripBooking trip, {bool reportOnly = false}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReviewFlowScreen(
          repository: _repository,
          trip: trip,
          reportOnly: reportOnly,
          picker: widget.picker,
        ),
      ),
    );
    if (changed == true && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Ongoing'),
              Tab(text: 'Completed'),
              Tab(text: 'My reports'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final phase in ['upcoming', 'ongoing', 'completed'])
                  _TripList(
                    phase: phase,
                    trips: _trips,
                    onRetry: () => setState(_reload),
                    onReview: _open,
                  ),
                _ReportList(
                  reports: _reports,
                  repository: _repository,
                  onChanged: () => setState(_reload),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TripList extends StatelessWidget {
  const _TripList({
    required this.phase,
    required this.trips,
    required this.onRetry,
    required this.onReview,
  });

  final String phase;
  final Future<List<TripBooking>> trips;
  final VoidCallback onRetry;
  final Future<void> Function(TripBooking trip, {bool reportOnly}) onReview;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<TripBooking>>(
    future: trips,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(HavenIcons.refresh),
            label: const Text('Trips could not be loaded. Retry'),
          ),
        );
      }
      final items = snapshot.data!
          .where((trip) => trip.phase == phase)
          .toList(growable: false);
      if (items.isEmpty) {
        return Center(child: Text('No $phase stays.'));
      }
      return ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) =>
            _TripCard(trip: items[index], onAction: onReview),
      );
    },
  );
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.onAction});

  final TripBooking trip;
  final Future<void> Function(TripBooking trip, {bool reportOnly}) onAction;

  @override
  Widget build(BuildContext context) {
    final image = trip.imageUrl.isEmpty
        ? const Icon(HavenIcons.hotelOutlined, size: 32)
        : Image.network(
            trip.imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(HavenIcons.hotelOutlined, size: 32),
          );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(width: 80, height: 80, child: image),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.propertyName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (trip.location.isNotEmpty)
                        Text(
                          trip.location,
                          style: const TextStyle(color: HavenTheme.muted),
                        ),
                      Text(
                        '${formatTripDate(trip.checkIn)} – ${formatTripDate(trip.checkOut)} · ${trip.nights} night${trip.nights == 1 ? '' : 's'}',
                      ),
                      Text(
                        'Ref ${trip.reference} · TZS ${trip.totalTzs} · Payment ${trip.paymentStatus}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: HavenTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _actions(context),
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    switch (trip.phase) {
      case 'ongoing':
        return OutlinedButton.icon(
          onPressed: () => onAction(trip, reportOnly: true),
          icon: const Icon(HavenIcons.warningAmberRounded),
          label: const Text('Report an urgent issue'),
        );
      case 'completed':
        final review = trip.review;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (review != null) ...[
              const Chip(
                avatar: Icon(HavenIcons.checkCircle, size: 18),
                label: Text('Review Submitted'),
              ),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => Dialog(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(8),
                        child: GuestReviewCard(review: review),
                      ),
                    ),
                  ),
                ),
                child: const Text('View review'),
              ),
            ] else if (trip.canReview)
              FilledButton.icon(
                onPressed: () => onAction(trip),
                icon: const Icon(HavenIcons.starRounded),
                label: const Text('Write a Review'),
              )
            else
              Text(
                trip.reviewBlockedReason ?? 'Review not available.',
                style: const TextStyle(color: HavenTheme.muted),
              ),
            TextButton(
              onPressed: () => onAction(trip, reportOnly: true),
              child: const Text('Report a problem'),
            ),
          ],
        );
      default:
        return const Text(
          'Reviews open after your stay is completed.',
          style: TextStyle(color: HavenTheme.muted),
        );
    }
  }
}

class _ReportList extends StatelessWidget {
  const _ReportList({
    required this.reports,
    required this.repository,
    required this.onChanged,
  });

  final Future<List<ProblemReportItem>> reports;
  final ReviewRepository repository;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<ProblemReportItem>>(
    future: reports,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return const Center(child: Text('Reports could not be loaded.'));
      }
      final items = snapshot.data!;
      if (items.isEmpty) {
        return const Center(child: Text('You have not submitted any reports.'));
      }
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          for (final report in items)
            Card(
              child: ExpansionTile(
                title: Text(
                  '${report.reference} · ${problemCategories[report.category] ?? report.category}',
                ),
                subtitle: Text(
                  '${report.propertyName} · ${reportStatusLabels[report.status] ?? report.status}',
                ),
                childrenPadding: const EdgeInsets.all(12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report.description),
                  for (final note in report.notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${note.authorRole == 'CUSTOMER' ? 'You' : 'HavenLink'}: ${note.body}',
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _reply(context, report),
                      child: const Text('Add a message'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );

  Future<void> _reply(BuildContext context, ProblemReportItem report) async {
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a message'),
        content: TextField(controller: controller, minLines: 2, maxLines: 5),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || message.isEmpty) return;
    await repository.replyToMyReport(report.id, message);
    onChanged();
  }
}
