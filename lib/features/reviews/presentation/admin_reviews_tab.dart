import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../data/review_repository.dart';

class AdminReviewsTab extends StatefulWidget {
  const AdminReviewsTab({required this.tokenProvider, super.key});

  final String? Function() tokenProvider;

  @override
  State<AdminReviewsTab> createState() => _AdminReviewsTabState();
}

class _AdminReviewsTabState extends State<AdminReviewsTab> {
  late final ReviewRepository _repository;
  late Future<Map<String, dynamic>> _queue;
  late Future<List<Map<String, dynamic>>> _audit;
  String _status = 'all';
  bool _reportedOnly = true;

  @override
  void initState() {
    super.initState();
    _repository = ReviewRepository(tokenProvider: widget.tokenProvider);
    _reload();
  }

  void _reload() {
    _queue = _repository.loadAdminReviews(
      status: _status == 'all' ? null : _status,
      reportedOnly: _reportedOnly,
    );
    _audit = _repository.loadAdminAuditEvents();
    // The audit view can remain unmounted when the main queue fails.
    _audit.ignore();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _queue,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: TextButton.icon(
            onPressed: () => setState(_reload),
            icon: const Icon(HavenIcons.refresh),
            label: Text(snapshot.error.toString()),
          ),
        );
      }
      final data = snapshot.data ?? const {};
      final stats = data['stats'] as Map<String, dynamic>? ?? const {};
      final rows = (data['reviews'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      return Column(
        children: [
          _ReviewStats(stats: stats),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: _status,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _status = value;
                      _reload();
                    });
                  },
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All statuses')),
                    DropdownMenuItem(
                      value: 'published',
                      child: Text('Published'),
                    ),
                    DropdownMenuItem(value: 'hidden', child: Text('Hidden')),
                    DropdownMenuItem(
                      value: 'rejected',
                      child: Text('Rejected'),
                    ),
                  ],
                ),
                FilterChip(
                  selected: _reportedOnly,
                  label: const Text('Reported only'),
                  onSelected: (value) => setState(() {
                    _reportedOnly = value;
                    _reload();
                  }),
                ),
                IconButton(
                  tooltip: 'Refresh review queue',
                  onPressed: () => setState(_reload),
                  icon: const Icon(HavenIcons.refresh),
                ),
              ],
            ),
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _audit,
            builder: (context, auditSnapshot) {
              final events = auditSnapshot.data ?? const [];
              if (events.isEmpty) return const SizedBox.shrink();
              return ExpansionTile(
                title: Text('Review moderation audit (${events.length})'),
                children: events
                    .take(10)
                    .map((event) {
                      final actor =
                          event['actor'] as Map<String, dynamic>? ?? const {};
                      final metadata =
                          event['metadata'] as Map<String, dynamic>? ??
                          const {};
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${actor['fullName'] ?? 'Administrator'} · ${metadata['previousStatus'] ?? ''} → ${metadata['status'] ?? ''}',
                        ),
                        subtitle: Text(
                          '${metadata['reason'] ?? ''} · ${event['createdAt'] ?? ''}',
                        ),
                      );
                    })
                    .toList(growable: false),
              );
            },
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No reviews match this queue.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) => _ModerationCard(
                      review: rows[index],
                      onModerate: _moderate,
                    ),
                  ),
          ),
        ],
      );
    },
  );

  Future<void> _moderate(Map<String, dynamic> review, String status) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _ModerationReasonDialog(status: status),
    );
    if (reason == null || !mounted) return;
    try {
      await _repository.moderateReview(
        reviewId: review['id'] as String,
        status: status,
        reason: reason,
      );
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review moderation saved and audited.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }
}

class _ReviewStats extends StatelessWidget {
  const _ReviewStats({required this.stats});

  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _StatChip(label: 'Published', value: stats['published'] ?? 0),
        _StatChip(
          label: 'Pending reports',
          value: stats['pendingReports'] ?? 0,
        ),
        _StatChip(label: 'Hidden', value: stats['hidden'] ?? 0),
        _StatChip(label: 'Rejected', value: stats['rejected'] ?? 0),
        _StatChip(
          label: 'Average',
          value: (stats['averageRating'] as num?)?.toStringAsFixed(2) ?? '0.00',
        ),
      ],
    ),
  );
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final Object value;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text('$label · $value'),
    visualDensity: VisualDensity.compact,
  );
}

class _ModerationCard extends StatelessWidget {
  const _ModerationCard({required this.review, required this.onModerate});

  final Map<String, dynamic> review;
  final Future<void> Function(Map<String, dynamic>, String) onModerate;

  @override
  Widget build(BuildContext context) {
    final property = review['property'] as Map<String, dynamic>? ?? const {};
    final reviewer = review['reviewer'] as Map<String, dynamic>? ?? const {};
    final reports = (review['reportRecords'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final status = review['status'] as String? ?? 'published';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${property['name'] ?? 'Stay'} · ${reviewer['fullName'] ?? 'Guest'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(label: Text(status), visualDensity: VisualDensity.compact),
              ],
            ),
            Text(
              '${review['overallRating'] ?? 0} / 5 · ${property['neighborhood'] ?? ''}, ${property['city'] ?? ''}',
            ),
            if ((review['title'] as String? ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  review['title'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            if ((review['comment'] as String? ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(review['comment'] as String),
              ),
            for (final report in reports)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  HavenIcons.flagOutlined,
                  color: HavenTheme.muted,
                ),
                title: Text('Report: ${report['reason'] ?? ''}'),
                subtitle: Text(
                  'From ${(report['reporter'] as Map<String, dynamic>?)?['fullName'] ?? 'customer'} · ${report['status'] ?? 'pending'}',
                ),
              ),
            if ((review['moderationReason'] as String? ?? '').isNotEmpty)
              Text('Last decision: ${review['moderationReason']}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (status != 'hidden')
                  OutlinedButton.icon(
                    onPressed: () => onModerate(review, 'hidden'),
                    icon: const Icon(HavenIcons.visibilityOffOutlined),
                    label: const Text('Hide'),
                  ),
                if (status != 'published')
                  OutlinedButton.icon(
                    onPressed: () => onModerate(review, 'published'),
                    icon: const Icon(HavenIcons.visibilityOutlined),
                    label: const Text('Restore'),
                  ),
                if (status != 'rejected')
                  TextButton.icon(
                    onPressed: () => onModerate(review, 'rejected'),
                    icon: const Icon(HavenIcons.blockOutlined),
                    label: const Text('Reject'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModerationReasonDialog extends StatefulWidget {
  const _ModerationReasonDialog({required this.status});

  final String status;

  @override
  State<_ModerationReasonDialog> createState() =>
      _ModerationReasonDialogState();
}

class _ModerationReasonDialogState extends State<_ModerationReasonDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${widget.status[0].toUpperCase()}${widget.status.substring(1)} review',
    ),
    content: TextField(
      controller: _controller,
      autofocus: true,
      minLines: 2,
      maxLines: 4,
      maxLength: 1000,
      decoration: InputDecoration(
        labelText: 'Moderation reason',
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save decision')),
    ],
  );

  void _save() {
    if (_controller.text.trim().length < 5) {
      setState(() => _error = 'Provide a reason of at least 5 characters.');
      return;
    }
    Navigator.pop(context, _controller.text.trim());
  }
}
