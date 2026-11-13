import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../../core/config/env_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/review_models.dart';
import 'star_rating.dart';

String reviewPhotoUrl(String path) =>
    path.startsWith('http') ? path : EnvConfig.endpoint(path).toString();

String _monthYear(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

/// A published guest review as shown on a Stays property page.
class GuestReviewCard extends StatelessWidget {
  const GuestReviewCard({
    required this.review,
    this.canReport = false,
    this.onReport,
    super.key,
  });

  final GuestReview review;
  final bool canReport;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final initials = review.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final stay = review.stayDate;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: HavenTheme.lightMint,
                  child: Text(
                    initials.isEmpty ? 'G' : initials,
                    style: const TextStyle(color: HavenTheme.forest),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        stay == null
                            ? 'Reviewed ${_monthYear(review.createdAt)}'
                            : 'Stayed ${_monthYear(stay)}',
                        style: const TextStyle(
                          color: HavenTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canReport)
                  IconButton(
                    tooltip: 'Report review',
                    onPressed: onReport,
                    icon: const Icon(HavenIcons.flagOutlined, size: 19),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StarDisplay(rating: review.overallRating),
                Text(
                  review.overallRating.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Icon(
                  HavenIcons.verifiedOutlined,
                  size: 16,
                  color: HavenTheme.forest,
                ),
                const Text(
                  'Verified Stay',
                  style: TextStyle(color: HavenTheme.forest, fontSize: 12),
                ),
              ],
            ),
            Text(
              'Published ${review.createdAt.day}/${review.createdAt.month}/${review.createdAt.year}',
              style: const TextStyle(color: HavenTheme.muted, fontSize: 12),
            ),
            if ((review.title ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                review.title!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if ((review.comment ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(review.comment!),
            ],
            if (review.images.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final image in review.images)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        reviewPhotoUrl(image),
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        semanticLabel: 'Guest photo',
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox(
                              width: 88,
                              height: 88,
                              child: Icon(HavenIcons.imageNotSupportedOutlined),
                            ),
                      ),
                    ),
                ],
              ),
            ],
            if (review.criteria.values.any((value) => value > 0)) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final field in reviewRatingFields)
                    if ((review.criteria[field] ?? 0) > 0)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          '${reviewCategoryLabels[field]} ${review.criteria[field]}★',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                ],
              ),
            ],
            if ((review.agentResponse ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: HavenTheme.veryLightMint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: HavenTheme.forest.withValues(alpha: 0.15),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Response from the host',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(review.agentResponse!),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
