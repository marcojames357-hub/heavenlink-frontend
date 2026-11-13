import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PortalPageHeader extends StatelessWidget {
  const PortalPageHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.action,
    super.key,
  });
  final String eyebrow, title, subtitle;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final copy = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: HavenTheme.forest,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: HavenTheme.muted),
          ),
        ],
      );
      if (constraints.maxWidth < 600 && action != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [copy, const SizedBox(height: 16), action!],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: copy),
          const SizedBox(width: 16),
          action ??
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: HavenTheme.lightMint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: HavenTheme.forest, size: 22),
              ),
        ],
      );
    },
  );
}
