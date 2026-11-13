import 'package:flutter/material.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import '../theme/haven_icons.dart';

class HavenBookingProgress extends StatelessWidget {
  const HavenBookingProgress({required this.current, super.key});
  final int current;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final (i, label) in [
            'Property',
            'Room & dates',
            'Payment',
            'Confirmation',
          ].indexed) ...[
            if (i > 0)
              Container(
                width: constraints.maxWidth < 600 ? 16 : 32,
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: HavenTheme.border,
              ),
            Semantics(
              label: '${context.tr(label)}, ${i + 1} / 4',
              selected: i == current,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: i <= current
                        ? HavenTheme.forest
                        : HavenTheme.lightMint,
                    foregroundColor: i <= current
                        ? HavenTheme.white
                        : HavenTheme.muted,
                    child: i < current
                        ? const Icon(HavenIcons.check, size: 14)
                        : Text(
                            '${i + 1}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  if (constraints.maxWidth >= 650) ...[
                    const SizedBox(width: 7),
                    Text(
                      context.tr(label),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: i <= current
                            ? HavenTheme.forest
                            : HavenTheme.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Keeps the existing form children and submit callbacks while adapting their
/// presentation to the two-column payment design.
class HavenCheckoutLayout extends StatelessWidget {
  const HavenCheckoutLayout({
    required this.children,
    this.showProgress = true,
    this.progress = 2,
    super.key,
  });
  final List<Widget> children;
  final bool showProgress;
  final int progress;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final split = children.indexWhere(
        (w) => w.key == const Key('checkout-summary'),
      );
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showProgress) HavenBookingProgress(current: progress),
            if (constraints.maxWidth >= 900 && split > 0)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children.take(split).toList(),
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children.skip(split).toList(),
                    ),
                  ),
                ],
              )
            else
              ...children,
          ],
        ),
      );
    },
  );
}
