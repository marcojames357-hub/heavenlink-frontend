import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/formatters/currency_formatter.dart';
import '../../../core/theme/app_theme.dart';
import '../data/financial_management_repository.dart';

class AdminFinancialOverviewScreen extends StatefulWidget {
  const AdminFinancialOverviewScreen({required this.tokenProvider, super.key});

  final String? Function() tokenProvider;

  @override
  State<AdminFinancialOverviewScreen> createState() =>
      _AdminFinancialOverviewScreenState();
}

class _AdminFinancialOverviewScreenState
    extends State<AdminFinancialOverviewScreen> {
  late final _repository = FinancialManagementRepository(
    tokenProvider: widget.tokenProvider,
  );
  Map<String, dynamic>? _overview;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _repository.loadAdminOverview();
      if (mounted) {
        setState(() {
          _overview = result;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  int _value(String key) => (_overview?[key] as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> _list(String key) =>
      (_overview?[key] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    if (_loading && _overview == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _overview == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(HavenIcons.cloudOffOutlined, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(HavenIcons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    final agents =
        _overview?['agentCounts'] as Map<String, dynamic>? ?? const {};
    final recordCounts =
        (_overview?['financialRecordCounts'] as List<dynamic>? ?? const [])
            .whereType<num>()
            .map((value) => value.toInt())
            .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Financial Oversight',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh financial oversight',
                onPressed: _load,
                icon: const Icon(HavenIcons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Agent-reported activity is separate from Haven Link platform payment receipts.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 560
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - 12 * (columns - 1)) / columns;
              final items = [
                (
                  'Rental agents',
                  '${agents['rental'] ?? 0}',
                  HavenIcons.homeWorkOutlined,
                ),
                (
                  'Stay agents',
                  '${agents['stays'] ?? 0}',
                  HavenIcons.hotelOutlined,
                ),
                (
                  'Properties',
                  '${_value('totalProperties')}',
                  HavenIcons.apartment,
                ),
                (
                  'Unresolved alerts',
                  '${_list('unresolvedAlerts').length}',
                  HavenIcons.notificationsActiveOutlined,
                ),
                (
                  'Records needing review',
                  '${_list('financialRecordsRequireReview').length}',
                  HavenIcons.factCheckOutlined,
                ),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: items
                    .map(
                      (item) => SizedBox(
                        width: width,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(item.$3, color: HavenTheme.forest),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.$1),
                                      Text(
                                        item.$2,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 12),
          _ActivityTrend(records: _list('financialActivityByMonth')),
          const SizedBox(height: 12),
          _PropertyPerformance(records: _list('propertyPerformance')),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Financial record coverage',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Properties with records: ${_value('propertiesWithFinancialRecords')}',
                  ),
                  Text('Rent obligations: ${_recordCount(recordCounts, 0)}'),
                  Text('Operating expenses: ${_recordCount(recordCounts, 1)}'),
                  Text('Utility bills: ${_recordCount(recordCounts, 2)}'),
                  Text(
                    'Staff payment obligations: ${_recordCount(recordCounts, 3)}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Financial activity (reported separately)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  _FinancialValue(
                    label: 'Agent-reported rental receipts (offline)',
                    value: _value('agentReportedRentalReceiptsTzs'),
                  ),
                  _FinancialValue(
                    label: 'Confirmed stay booking gross',
                    value: _value('confirmedStayBookingGrossTzs'),
                  ),
                  _FinancialValue(
                    label: 'Verified Haven Link payment receipts',
                    value: _value('verifiedPlatformPaymentReceiptsTzs'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'These figures are not agent payouts or a platform commission calculation.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ExpenseCategoryOverview(records: _list('expensesByCategory')),
          const SizedBox(height: 12),
          _AlertSeveritySummary(records: _list('unresolvedAlertsBySeverity')),
          const SizedBox(height: 12),
          _DiscrepancyList(records: _list('financialRecordsRequireReview')),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unresolved financial alerts',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_list('unresolvedAlerts').isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No unresolved financial alerts.'),
                    )
                  else
                    ..._list('unresolvedAlerts').map((alert) {
                      final property =
                          alert['property'] as Map<String, dynamic>? ??
                          const {};
                      final severity =
                          alert['severity'] as String? ?? 'warning';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          HavenIcons.warningAmberOutlined,
                          color: severity == 'critical'
                              ? HavenTheme.danger
                              : HavenTheme.gold,
                        ),
                        title: Text(
                          alert['title'] as String? ?? 'Financial alert',
                        ),
                        subtitle: Text(
                          '${property['name'] ?? 'Property'} · ${alert['description'] ?? ''}',
                        ),
                        trailing: Text(severity.toUpperCase()),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Financial changes are recorded in the existing system audit log. '
                'Only authorized agents can view or change records for their own properties.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

int _recordCount(List<int> counts, int index) =>
    counts.length > index ? counts[index] : 0;

class _ActivityTrend extends StatelessWidget {
  const _ActivityTrend({required this.records});
  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Financial activity by month',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (records.isEmpty)
            const Text('No verified or agent-reported receipts recorded.')
          else
            SizedBox(
              height: 190,
              child: CustomPaint(
                painter: _AdminTrendPainter(
                  rental: records
                      .map(
                        (item) =>
                            (item['rentalReceiptsTzs'] as num?)?.toInt() ?? 0,
                      )
                      .toList(),
                  stays: records
                      .map(
                        (item) =>
                            (item['stayBookingGrossTzs'] as num?)?.toInt() ?? 0,
                      )
                      .toList(),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          const SizedBox(height: 8),
          const Wrap(
            spacing: 16,
            children: [
              _TrendLegend(
                color: HavenTheme.forest,
                label: 'Rental offline receipts',
              ),
              _TrendLegend(color: Colors.blue, label: 'Stay booking gross'),
            ],
          ),
        ],
      ),
    ),
  );
}

class _AdminTrendPainter extends CustomPainter {
  _AdminTrendPainter({required this.rental, required this.stays});
  final List<int> rental;
  final List<int> stays;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [...rental, ...stays];
    final maximum = values.isEmpty
        ? 1.0
        : values
              .fold<int>(0, (a, b) => a > b ? a : b)
              .toDouble()
              .clamp(1, double.infinity);
    final baseline = size.height - 4;
    final step = size.width / (rental.length + 1);
    final paintRental = Paint()..color = HavenTheme.forest;
    final paintStays = Paint()..color = Colors.blue;
    for (var index = 0; index < rental.length; index++) {
      final x = step * (index + 1);
      final leftHeight = rental[index] / maximum * baseline;
      final rightHeight = stays[index] / maximum * baseline;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 9, baseline - leftHeight, 7, leftHeight),
          const Radius.circular(3),
        ),
        paintRental,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + 2, baseline - rightHeight, 7, rightHeight),
          const Radius.circular(3),
        ),
        paintStays,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AdminTrendPainter oldDelegate) =>
      oldDelegate.rental != rental || oldDelegate.stays != stays;
}

class _TrendLegend extends StatelessWidget {
  const _TrendLegend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircleAvatar(radius: 5, backgroundColor: color),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _PropertyPerformance extends StatelessWidget {
  const _PropertyPerformance({required this.records});
  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) {
    final visible = records
        .where(
          (item) =>
              (item['revenueTzs'] as num? ?? 0) != 0 ||
              (item['expenseTzs'] as num? ?? 0) != 0,
        )
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Property performance',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('No property-level financial activity yet.'),
              )
            else
              ...visible.map((item) {
                final model = item['businessModel'] == 'bookable'
                    ? 'Stays'
                    : 'Rentals';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['propertyName'] as String? ?? 'Property'),
                  subtitle: Text(
                    '$model · Revenue ${formatTzs((item['revenueTzs'] as num?)?.toInt() ?? 0)}'
                    ' · Expenses ${formatTzs((item['expenseTzs'] as num?)?.toInt() ?? 0)}',
                  ),
                  trailing: Text(
                    formatTzs(
                      (item['operatingProfitTzs'] as num?)?.toInt() ?? 0,
                    ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _AlertSeveritySummary extends StatelessWidget {
  const _AlertSeveritySummary({required this.records});
  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unresolved alerts by severity',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Wrap(
            spacing: 20,
            children: ['critical', 'warning', 'informational'].map((severity) {
              final item = records
                  .where((item) => item['severity'] == severity)
                  .firstOrNull;
              return Chip(label: Text('$severity: ${item?['count'] ?? 0}'));
            }).toList(),
          ),
        ],
      ),
    ),
  );
}

class _DiscrepancyList extends StatelessWidget {
  const _DiscrepancyList({required this.records});
  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Records requiring review',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'No current payment or ledger discrepancies detected.',
              ),
            )
          else
            ...records.map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  HavenIcons.reportGmailerrorredOutlined,
                  color: item['severity'] == 'critical'
                      ? HavenTheme.danger
                      : HavenTheme.gold,
                ),
                title: Text(
                  '${item['propertyName'] ?? 'Property'} · ${item['type']}',
                ),
                subtitle: Text(item['description'] as String? ?? ''),
              ),
            ),
        ],
      ),
    ),
  );
}

class _FinancialValue extends StatelessWidget {
  const _FinancialValue({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(formatTzs(value), style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}

class _ExpenseCategoryOverview extends StatelessWidget {
  const _ExpenseCategoryOverview({required this.records});
  final List<Map<String, dynamic>> records;

  @override
  Widget build(BuildContext context) {
    final maximum = records.fold<int>(0, (value, item) {
      final amount = (item['amountTzs'] as num?)?.toInt() ?? 0;
      return amount > value ? amount : value;
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Operating expenses by category',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No expense records.'),
              )
            else
              ...records.map((item) {
                final value = (item['amountTzs'] as num?)?.toInt() ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('${item['category'] ?? 'Other'}'),
                          ),
                          Text(formatTzs(value)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: maximum == 0 ? 0 : value / maximum,
                        color: HavenTheme.forest,
                        backgroundColor: HavenTheme.lightMint,
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
