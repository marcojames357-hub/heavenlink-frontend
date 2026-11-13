import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/theme/app_theme.dart';
import '../data/review_repository.dart';
import '../domain/review_models.dart';
import 'widgets/guest_review_card.dart';
import 'widgets/star_rating.dart';

class PropertyReviewsSection extends StatefulWidget {
  const PropertyReviewsSection({
    required this.propertyId,
    required this.tokenProvider,
    this.canReport = false,
    this.repository,
    super.key,
  });

  final String propertyId;
  final String? Function() tokenProvider;
  final bool canReport;
  final ReviewRepository? repository;

  @override
  State<PropertyReviewsSection> createState() => _PropertyReviewsSectionState();
}

class _PropertyReviewsSectionState extends State<PropertyReviewsSection> {
  late final ReviewRepository _repository;
  late Future<PropertyReviewPage> _reviews;
  var _page = 1;
  var _sort = 'newest';
  int? _rating;
  String? _category;
  var _withPhotos = false;

  bool get _filtered => _rating != null || _category != null || _withPhotos;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        ReviewRepository(tokenProvider: widget.tokenProvider);
    _load();
  }

  void _load() {
    _reviews = _repository.loadPropertyReviews(
      propertyId: widget.propertyId,
      page: _page,
      sort: _sort,
      rating: _rating,
      category: _category,
      withPhotos: _withPhotos,
    );
  }

  void _apply(VoidCallback change) => setState(() {
    change();
    _page = 1;
    _load();
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PropertyReviewPage>(
      future: _reviews,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Row(
            children: [
              const Expanded(child: Text('Reviews could not be loaded.')),
              IconButton(
                tooltip: 'Retry loading reviews',
                onPressed: () => setState(_load),
                icon: const Icon(HavenIcons.refresh),
              ),
            ],
          );
        }
        final result = snapshot.data!;
        final summary = result.summary;
        final hasAnyReviews = summary.count > 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ReviewOverview(summary: summary),
            if (!hasAnyReviews)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'No reviews yet. Be the first verified guest to share your experience.',
                ),
              )
            else ...[
              const SizedBox(height: 20),
              Text(
                'Rating breakdown',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              _CriteriaBars(criteria: summary.criteria),
              if (summary.mentions.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text(
                  'Guests mention',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: summary.mentions
                      .map(
                        (mention) => Chip(
                          label: Text('${mention.label} · ${mention.count}'),
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(
                            color: HavenTheme.forest.withValues(alpha: 0.18),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              const Divider(height: 32),
              Text(
                'Guest reviews (${summary.count})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _Filters(
                sort: _sort,
                rating: _rating,
                category: _category,
                withPhotos: _withPhotos,
                onSort: (value) => _apply(() => _sort = value),
                onRating: (value) => _apply(() => _rating = value),
                onCategory: (value) => _apply(() => _category = value),
                onPhotos: (value) => _apply(() => _withPhotos = value),
              ),
              if (result.reviews.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    _filtered
                        ? 'No reviews match these filters.'
                        : 'No published reviews yet.',
                  ),
                )
              else ...[
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 720 ? 2 : 1;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 16) / columns;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        for (final review in result.reviews)
                          SizedBox(
                            width: width,
                            child: GuestReviewCard(
                              review: review,
                              canReport: widget.canReport,
                              onReport: () => _report(review),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                if (result.pages > 1)
                  Align(
                    alignment: Alignment.center,
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      children: [
                        IconButton(
                          tooltip: 'Previous reviews',
                          onPressed: _page > 1
                              ? () => setState(() {
                                  _page--;
                                  _load();
                                })
                              : null,
                          icon: const Icon(HavenIcons.chevronLeft),
                        ),
                        Text('Page ${result.page} of ${result.pages}'),
                        IconButton(
                          tooltip: 'Next reviews',
                          onPressed: _page < result.pages
                              ? () => setState(() {
                                  _page++;
                                  _load();
                                })
                              : null,
                          icon: const Icon(HavenIcons.chevronRight),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ],
        );
      },
    );
  }

  Future<void> _report(GuestReview review) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReportReviewDialog(),
    );
    if (reason == null || !mounted) return;
    try {
      await _repository.reportReview(reviewId: review.id, reason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review sent to the moderation team.')),
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

class _ReviewOverview extends StatelessWidget {
  const _ReviewOverview({required this.summary});

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.count == 0) {
      return Text(
        'Guest reviews',
        style: Theme.of(context).textTheme.titleLarge,
      );
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 4,
      children: [
        const Icon(HavenIcons.starRounded, color: starGold, size: 34),
        Text(
          summary.overall.toStringAsFixed(1),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(
          summary.count == 1
              ? 'Based on 1 verified stay'
              : 'Based on ${summary.count} verified stays',
          style: const TextStyle(color: HavenTheme.muted),
        ),
      ],
    );
  }
}

class _CriteriaBars extends StatelessWidget {
  const _CriteriaBars({required this.criteria});

  final Map<String, double> criteria;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 640 ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 24) / columns;
      return Wrap(
        spacing: 24,
        runSpacing: 10,
        children: [
          for (final field in reviewRatingFields)
            SizedBox(
              width: width,
              child: Semantics(
                label:
                    '${reviewCategoryLabels[field]}: ${(criteria[field] ?? 0).toStringAsFixed(1)} out of 5',
                excludeSemantics: true,
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        reviewCategoryLabels[field]!,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ((criteria[field] ?? 0) / 5).clamp(0, 1),
                          minHeight: 7,
                          backgroundColor: starGrey.withValues(alpha: 0.4),
                          color: starGold,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 38,
                      child: Text(
                        (criteria[field] ?? 0).toStringAsFixed(1),
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.sort,
    required this.rating,
    required this.category,
    required this.withPhotos,
    required this.onSort,
    required this.onRating,
    required this.onCategory,
    required this.onPhotos,
  });

  final String sort;
  final int? rating;
  final String? category;
  final bool withPhotos;
  final ValueChanged<String> onSort;
  final ValueChanged<int?> onRating;
  final ValueChanged<String?> onCategory;
  final ValueChanged<bool> onPhotos;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ChoiceChip(
        label: const Text('All reviews'),
        selected: rating == null && category == null && !withPhotos,
        onSelected: (_) {
          onRating(null);
          onCategory(null);
          onPhotos(false);
        },
      ),
      DropdownButton<String>(
        value: sort,
        underline: const SizedBox.shrink(),
        onChanged: (value) => value == null ? null : onSort(value),
        items: const [
          DropdownMenuItem(value: 'newest', child: Text('Most recent')),
          DropdownMenuItem(value: 'highest', child: Text('Highest rated')),
          DropdownMenuItem(value: 'lowest', child: Text('Lowest rated')),
        ],
      ),
      DropdownButton<int?>(
        value: rating,
        hint: const Text('Stars'),
        underline: const SizedBox.shrink(),
        onChanged: onRating,
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('Any rating')),
          for (var stars = 5; stars >= 1; stars--)
            DropdownMenuItem<int?>(value: stars, child: Text('$stars ★')),
        ],
      ),
      DropdownButton<String?>(
        value: category,
        hint: const Text('Category'),
        underline: const SizedBox.shrink(),
        onChanged: onCategory,
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Any category'),
          ),
          for (final field in reviewRatingFields)
            DropdownMenuItem<String?>(
              value: field,
              child: Text('${reviewCategoryLabels[field]} 4★+'),
            ),
        ],
      ),
      FilterChip(
        label: const Text('With photos'),
        selected: withPhotos,
        onSelected: onPhotos,
      ),
    ],
  );
}

class _ReportReviewDialog extends StatefulWidget {
  const _ReportReviewDialog();

  @override
  State<_ReportReviewDialog> createState() => _ReportReviewDialogState();
}

class _ReportReviewDialogState extends State<_ReportReviewDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Report this review'),
    content: TextField(
      controller: _reason,
      autofocus: true,
      minLines: 3,
      maxLines: 5,
      maxLength: 1000,
      decoration: InputDecoration(
        labelText: 'Why should an administrator review it?',
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Send report')),
    ],
  );

  void _submit() {
    if (_reason.text.trim().length < 5) {
      setState(() => _error = 'Please provide at least 5 characters.');
      return;
    }
    Navigator.pop(context, _reason.text.trim());
  }
}
