import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/haven_icons.dart';
import '../../features/properties/domain/property.dart';
import '../formatters/currency_formatter.dart';

/// Native translation of Make's chart / priority column / recent-records layout.
/// Bar heights and table cells always come from the supplied live listing data.
class PropertyPortfolioPanel extends StatelessWidget {
  const PropertyPortfolioPanel({
    required this.properties,
    required this.onManage,
    this.onActivity,
    this.title = 'Portfolio performance',
    this.manageLabel = 'Manage properties',
    super.key,
  });
  final List<Property> properties;
  final VoidCallback? onManage, onActivity;
  final String title, manageLabel;

  @override
  Widget build(BuildContext context) {
    final pending = properties
        .where((p) => p.listingStatus == ListingStatus.pendingReview)
        .length;
    final published = properties.where((p) => p.isPublic).length;
    final categories = PropertyCategory.values
        .where((c) => properties.any((p) => p.category == c))
        .toList();
    final bars = categories
        .map(
          (c) => (
            c.name.replaceAllMapped(
              RegExp(r'[A-Z]'),
              (m) => ' ${m[0]!.toLowerCase()}',
            ),
            properties.where((p) => p.category == c).length,
          ),
        )
        .toList();
    final maximum = bars.fold<int>(1, (m, b) => math.max(m, b.$2));
    final chart = _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 8),
              const Chip(label: Text('Current portfolio')),
            ],
          ),
          Text(
            'Listings by category',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 176,
            child: properties.isEmpty
                ? const Center(child: Text('No listing activity yet'))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final bar in bars)
                        Expanded(
                          child: Tooltip(
                            message: '${bar.$1}: ${bar.$2}',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    '${bar.$2}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    height: 130 * bar.$2 / maximum,
                                    decoration: BoxDecoration(
                                      color: HavenTheme.mintAccent,
                                      borderRadius: const BorderRadius.vertical(
                                        top: Radius.circular(6),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          const Divider(height: 24),
          Row(
            children: [
              for (final item in [
                ('Total', properties.length),
                ('Published', published),
                ('Pending', pending),
              ])
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$1,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item.$2}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
    final priorities = _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Priority actions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          _Action(
            icon: HavenIcons.pendingActions,
            title: 'Pending approval',
            subtitle: '$pending listings',
            onTap: onManage,
          ),
          _Action(
            icon: HavenIcons.homeWorkOutlined,
            title: manageLabel,
            subtitle: '${properties.length} properties',
            onTap: onManage,
          ),
          if (onActivity != null)
            _Action(
              icon: HavenIcons.calendarMonthOutlined,
              title: 'View activity',
              subtitle: 'Open your existing records',
              onTap: onActivity,
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [chart, const SizedBox(height: 20), priorities],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: chart),
                const SizedBox(width: 20),
                Expanded(flex: 3, child: priorities),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recent records',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: onManage,
                      child: const Text('View all'),
                    ),
                  ],
                ),
              ),
              if (properties.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No property records yet.'),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      for (final label in [
                        'Reference',
                        'Property',
                        'Type',
                        'Listed price',
                        'Status',
                        'Location',
                      ])
                        DataColumn(label: Text(label)),
                    ],
                    rows: [
                      for (final p in properties.take(6))
                        DataRow(
                          cells: [
                            DataCell(
                              Text(
                                p.id.length > 10 ? p.id.substring(0, 10) : p.id,
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 200,
                                child: Text(
                                  p.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                p.businessModel ==
                                        PropertyBusinessModel.contactUnlock
                                    ? 'Rental'
                                    : 'Stay',
                              ),
                            ),
                            DataCell(Text(formatTzs(p.priceTzs))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: HavenTheme.lightMint,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  p.listingStatus.label,
                                  style: const TextStyle(
                                    color: HavenTheme.forest,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(Text(p.city)),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: child),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: HavenTheme.lightMint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: HavenTheme.forest, size: 18),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: const Icon(HavenIcons.chevronRight, size: 16),
    ),
  );
}
