import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../data/review_repository.dart';
import '../domain/review_models.dart';
import 'widgets/guest_review_card.dart';
import 'widgets/star_rating.dart';

/// Stay agent: Reviews & Ratings plus assigned (non-sensitive) problem reports.
class AgentReviewsTab extends StatefulWidget {
  const AgentReviewsTab({
    required this.tokenProvider,
    this.repository,
    super.key,
  });

  final String? Function() tokenProvider;
  final ReviewRepository? repository;

  @override
  State<AgentReviewsTab> createState() => _AgentReviewsTabState();
}

class _AgentReviewsTabState extends State<AgentReviewsTab> {
  late final ReviewRepository _repository;
  late Future<Map<String, dynamic>> _reviews;
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
    _reviews = _repository.loadAgentReviews();
    _reports = _repository.loadAgentReports();
    // The second tab is lazy; observe failures until its FutureBuilder mounts.
    _reports.ignore();
  }

  Future<String?> _ask(String title, {String? hint}) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 6,
          maxLength: 1500,
          decoration: InputDecoration(hintText: hint),
        ),
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
    return text == null || text.length < 5 ? null : text;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: 'Reviews & Ratings'),
            Tab(text: 'Problem reports'),
          ],
        ),
        Expanded(child: TabBarView(children: [_reviewsView(), _reportsView()])),
      ],
    ),
  );

  Widget _reviewsView() => FutureBuilder<Map<String, dynamic>>(
    future: _reviews,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return const Center(child: Text('Reviews could not be loaded.'));
      }
      final data = snapshot.data!;
      final summary = ReviewSummary.fromJson(
        data['summary'] as Map<String, dynamic>? ?? const {},
      );
      final reviews = [
        for (final item in data['reviews'] as List<dynamic>? ?? const [])
          GuestReview.fromJson(item as Map<String, dynamic>),
      ];
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Icon(HavenIcons.starRounded, color: starGold, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  summary.count == 0
                      ? 'No reviews yet'
                      : '${summary.overall.toStringAsFixed(1)} from ${summary.count} verified stays',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          if (summary.count > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final field in reviewRatingFields)
                    Chip(
                      label: Text(
                        '${reviewCategoryLabels[field]} ${(summary.criteria[field] ?? 0).toStringAsFixed(1)}',
                      ),
                    ),
                ],
              ),
            ),
          for (final review in reviews)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                if (review.propertyName != null)
                  Text(
                    review.propertyName!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: HavenTheme.forest,
                    ),
                  ),
                GuestReviewCard(review: review),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final text = await _ask(
                        review.agentResponse == null
                            ? 'Public response'
                            : 'Update public response',
                        hint: 'Thank the guest and address their feedback',
                      );
                      if (text == null) return;
                      await _run(
                        () => _repository.respondToReview(review.id, text),
                      );
                    },
                    icon: const Icon(HavenIcons.reply),
                    label: Text(
                      review.agentResponse == null
                          ? 'Write a public response'
                          : 'Edit response',
                    ),
                  ),
                ),
              ],
            ),
        ],
      );
    },
  );

  Widget _reportsView() => FutureBuilder<List<ProblemReportItem>>(
    future: _reports,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return const Center(child: Text('Reports could not be loaded.'));
      }
      final items = snapshot.data!;
      if (items.isEmpty) {
        return const Center(child: Text('No problem reports assigned to you.'));
      }
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final report in items)
            Card(
              child: ExpansionTile(
                title: Text(
                  '${report.reference} · ${problemCategories[report.category] ?? report.category}',
                ),
                subtitle: Text(
                  '${report.propertyName} · ${report.severity == 'urgent' ? 'URGENT · ' : ''}${reportStatusLabels[report.status] ?? report.status}',
                ),
                childrenPadding: const EdgeInsets.all(12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report.description),
                  for (final note in report.notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('${note.authorRole}: ${note.body}'),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () async {
                          final text = await _ask('Reply');
                          if (text == null) return;
                          await _run(
                            () => _repository.replyAsAgent(report.id, text),
                          );
                        },
                        child: const Text('Reply'),
                      ),
                      TextButton(
                        onPressed: () async {
                          final text = await _ask('Proposed resolution');
                          if (text == null) return;
                          await _run(
                            () => _repository.replyAsAgent(
                              report.id,
                              text,
                              resolution: true,
                            ),
                          );
                        },
                        child: const Text('Propose resolution'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
