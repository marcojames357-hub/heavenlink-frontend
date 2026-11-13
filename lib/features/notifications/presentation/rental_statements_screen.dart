import 'package:flutter/material.dart';

import '../../../core/formatters/currency_formatter.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import 'notification_center_screen.dart';

/// Read-only rent statements for tenants linked to a rent record by their agent.
class RentalStatementsScreen extends StatefulWidget {
  const RentalStatementsScreen({required this.repository, super.key});

  final NotificationRepository repository;

  @override
  State<RentalStatementsScreen> createState() => _RentalStatementsScreenState();
}

class _RentalStatementsScreenState extends State<RentalStatementsScreen> {
  late Future<List<Map<String, dynamic>>> _future = widget.repository
      .rentalStatements();

  Future<void> _reload() async {
    setState(() => _future = widget.repository.rentalStatements());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Rental payments'))),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(context.tr('Could not load statements')));
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return Center(
              child: Text(context.tr('No rent records are linked to you yet.')),
            );
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Text(
                    context.tr(
                      'Amounts are the payments your agent has recorded. '
                      'Some may have been made outside Haven Link.',
                    ),
                    style: const TextStyle(color: HavenTheme.muted),
                  );
                }
                return _StatementCard(item: items[index - 1]);
              },
            ),
          );
        },
      ),
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final outstanding = (item['outstandingTzs'] as num?) ?? 0;
    final settled = outstanding <= 0;
    final unit = item['unit'] as String?;
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
                    '${item['property'] ?? ''}'
                    '${unit == null || unit.isEmpty ? '' : ' · $unit'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(
                  label: Text(context.tr(settled ? 'Paid' : 'Outstanding')),
                  backgroundColor: settled
                      ? HavenTheme.lightMint
                      : Colors.orange.shade50,
                ),
              ],
            ),
            Text(
              '${item['billingMonth'] ?? ''} · due ${item['dueDate'] ?? ''}',
            ),
            const SizedBox(height: 8),
            Text(
              '${context.tr('Expected')}: '
              '${formatTzs((item['expectedTzs'] as num?) ?? 0)}',
            ),
            Text(
              '${context.tr('Recorded paid')}: '
              '${formatTzs((item['recordedPaidTzs'] as num?) ?? 0)}',
            ),
            if (!settled)
              Text(
                '${context.tr('Outstanding')}: ${formatTzs(outstanding)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            if (item['tenancyEnded'] == true) Text(context.tr('Tenancy ended')),
          ],
        ),
      ),
    );
  }
}
