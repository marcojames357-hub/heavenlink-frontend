import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import '../theme/haven_icons.dart';

class PortalSidebarHeading extends StatelessWidget {
  const PortalSidebarHeading({required this.workspace, super.key});

  final String workspace;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: HavenTheme.forest,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                  bottomLeft: Radius.circular(5),
                ),
              ),
              child: const Icon(
                HavenIcons.homeRounded,
                color: HavenTheme.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Haven Link',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: HavenTheme.lightMint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('Current workspace').toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: HavenTheme.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                workspace,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class PortalSidebarItem extends StatelessWidget {
  const PortalSidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? HavenTheme.white : HavenTheme.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? HavenTheme.forest : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          minLeadingWidth: 18,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: Icon(icon, size: 18, color: color),
          title: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
