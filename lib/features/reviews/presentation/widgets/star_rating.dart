import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../domain/review_models.dart';

const starGold = Color(0xFFF5B301);
const starGrey = Color(0xFFC9CED6);

/// Interactive 1-5 star control with keyboard and screen-reader support.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    required this.label,
    required this.question,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String question;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(question, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  key: ValueKey('star-$label-$star'),
                  tooltip: '$label: $star star${star == 1 ? '' : 's'}',
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => onChanged(star),
                  isSelected: star == value,
                  icon: Icon(
                    star <= value
                        ? HavenIcons.starRounded
                        : HavenIcons.starOutlineRounded,
                    size: 34,
                    color: star <= value ? starGold : starGrey,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  value == 0 ? 'Tap to rate' : ratingWords[value],
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: value == 0 ? theme.hintColor : starGold,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class StarDisplay extends StatelessWidget {
  const StarDisplay({required this.rating, this.size = 16, super.key});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${rating.toStringAsFixed(1)} out of 5 stars',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          Icon(
            rating >= star - 0.25
                ? HavenIcons.starRounded
                : rating >= star - 0.75
                ? HavenIcons.starHalfRounded
                : HavenIcons.starOutlineRounded,
            size: size,
            color: rating >= star - 0.75 ? starGold : starGrey,
          ),
      ],
    ),
  );
}
