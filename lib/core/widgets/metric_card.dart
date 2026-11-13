import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class HavenMetricCard extends StatelessWidget {
  const HavenMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color = HavenTheme.forest,
    this.note,
    super.key,
  });
  final String label, value;
  final IconData icon;
  final Color color;
  final String? note;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -.6,
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    ),
  );
}
