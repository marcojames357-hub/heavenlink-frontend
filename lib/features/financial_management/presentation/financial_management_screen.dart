import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/formatters/currency_formatter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/metric_card.dart';
import '../../properties/domain/property.dart';
import '../data/financial_management_repository.dart';
import 'tenancy_dialog.dart';

enum FinancialView { all, overview, expenses }

class FinancialManagementScreen extends StatefulWidget {
  const FinancialManagementScreen({
    required this.businessModel,
    required this.properties,
    required this.tokenProvider,
    this.view = FinancialView.all,
    super.key,
  });

  final PropertyBusinessModel businessModel;
  final List<Property> properties;
  final String? Function() tokenProvider;
  final FinancialView view;

  @override
  State<FinancialManagementScreen> createState() =>
      _FinancialManagementScreenState();
}

class _FinancialManagementScreenState extends State<FinancialManagementScreen> {
  late final FinancialManagementRepository _repository =
      FinancialManagementRepository(tokenProvider: widget.tokenProvider);
  Map<String, dynamic>? _data;
  String? _propertyId;
  String? _error;
  bool _loading = true;
  int _months = 6;

  bool get _showOverview => widget.view != FinancialView.expenses;
  bool get _showExpenses => widget.view != FinancialView.overview;

  bool get _isRental =>
      widget.businessModel == PropertyBusinessModel.contactUnlock;

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
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - _months + 1, 1);
    try {
      final result = await _repository.loadDashboard(
        businessModel: widget.businessModel.name,
        propertyId: _propertyId,
        from: from,
        to: now,
      );
      if (!mounted) return;
      setState(() {
        _data = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> _records(String key) =>
      (_data?[key] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

  Map<String, dynamic> get _summary =>
      _data?['summary'] as Map<String, dynamic>? ?? const {};

  int _amount(Map<String, dynamic> data, String key) =>
      (data[key] as num?)?.toInt() ?? 0;

  Future<void> _createRecord(String type) async {
    final selectedPropertyId =
        _propertyId ??
        (widget.properties.length == 1 ? widget.properties.single.id : null);
    if (selectedPropertyId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a property first.')));
      return;
    }
    final values = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _FinancialRecordDialog(type: type),
    );
    if (values == null) return;
    try {
      switch (type) {
        case 'rent':
          await _repository.createRentObligation(
            propertyId: selectedPropertyId,
            values: values,
          );
        case 'expense':
          await _repository.createExpense(
            propertyId: selectedPropertyId,
            values: values,
          );
        case 'bill':
          await _repository.createBill(
            propertyId: selectedPropertyId,
            values: values,
          );
        case 'staff':
          await _repository.createStaffObligation(
            propertyId: selectedPropertyId,
            values: values,
          );
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _recordPayment(String type, Map<String, dynamic> record) async {
    final propertyId = record['propertyId'] as String?;
    final recordId = record['id'] as String?;
    if (propertyId == null || recordId == null) return;
    final payment = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => const _PaymentDialog(),
    );
    if (payment == null) return;
    final amount = payment['amountTzs'] as int;
    final date = DateTime.now();
    final paymentDate =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final key = 'finance-$recordId-${DateTime.now().microsecondsSinceEpoch}';
    try {
      if (type == 'rent') {
        await _repository.recordRentPayment(
          propertyId: propertyId,
          obligationId: recordId,
          values: {
            'amountTzs': amount,
            'paymentDate': paymentDate,
            'idempotencyKey': key,
            'reference': payment['reference'],
          },
        );
      } else {
        await _repository.recordPayment(
          propertyId: propertyId,
          type: type,
          recordId: recordId,
          values: {
            'amountTzs': amount,
            'paymentDate': paymentDate,
            'method': payment['method'],
            'reference': payment['reference'],
            'idempotencyKey': key,
          },
        );
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _editTenancy(String type, Map<String, dynamic> record) async {
    final propertyId = record['propertyId'] as String?;
    final recordId = record['id'] as String?;
    if (propertyId == null || recordId == null) return;
    final values = await showTenancyDialog(context);
    if (values == null) return;
    try {
      await _repository.updateRentTenancy(
        propertyId: propertyId,
        obligationId: recordId,
        values: values,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Tenancy updated.')));
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _markAlertRead(String id) async {
    try {
      await _repository.markAlertRead(id);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _reverseRecord(String type, Map<String, dynamic> record) async {
    final propertyId = record['propertyId'] as String?;
    final recordId = record['id'] as String?;
    if (propertyId == null || recordId == null) return;
    final reasonController = TextEditingController();
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reverse financial record'),
          content: TextField(
            controller: reasonController,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'Explain why this record is being reversed',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = reasonController.text.trim();
                if (value.length < 3) return;
                Navigator.pop(context, value);
              },
              child: const Text('Reverse'),
            ),
          ],
        ),
      );
      if (reason == null) return;
      if (type == 'propertyExpense') {
        await _repository.reverseExpense(
          propertyId: propertyId,
          recordId: recordId,
          reason: reason,
        );
      } else {
        await _repository.reverseRecord(
          propertyId: propertyId,
          type: type,
          recordId: recordId,
          reason: reason,
        );
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      reasonController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _data == null) {
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.view == FinancialView.expenses
                ? 'Utilities & Expenses'
                : 'Financial Management',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 6),
          Text(
            widget.view == FinancialView.expenses
                ? 'Record utility bills, operating costs and optional staff payments.'
                : _isRental
                ? 'Track offline rent receipts, property costs and bills.'
                : 'Review confirmed booking activity and operating costs.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: HavenTheme.muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _propertyId,
                  decoration: const InputDecoration(labelText: 'Property'),
                  items: [
                    const DropdownMenuItem<String?>(
                      child: Text('All my properties'),
                    ),
                    ...widget.properties.map(
                      (property) => DropdownMenuItem(
                        value: property.id,
                        child: Text(property.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _propertyId = value);
                    _load();
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _months,
                  decoration: const InputDecoration(labelText: 'Date range'),
                  items: const [3, 6, 12]
                      .map(
                        (months) => DropdownMenuItem(
                          value: months,
                          child: Text('Last $months months'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _months = value);
                    _load();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Refresh financial data',
                onPressed: _load,
                icon: const Icon(HavenIcons.refresh),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          if (_showOverview) ...[
            _SummaryGrid(
              values: _summary,
              isRental: _isRental,
              amount: _amount,
            ),
            const SizedBox(height: 20),
            _SectionCard(
              title: _isRental
                  ? 'Monthly rent and expenses'
                  : 'Monthly revenue and expenses',
              child: _records('trends').isEmpty
                  ? const _EmptyMessage(
                      'No financial activity for this date range.',
                    )
                  : SizedBox(
                      height: 230,
                      child: _IncomeExpenseChart(
                        trends: _records('trends'),
                        amount: _amount,
                        isRental: _isRental,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
          ],
          if (_showExpenses) ...[
            _SectionCard(
              title: 'Expense distribution',
              child: _records('expensesByCategory').isEmpty
                  ? const _EmptyMessage('No operating expenses recorded yet.')
                  : Column(
                      children: _records('expensesByCategory')
                          .map(
                            (item) => _CategoryBar(
                              label: _label(
                                item['category'] as String? ?? 'other',
                              ),
                              amountTzs: _amount(item, 'amountTzs'),
                              maximum: _records('expensesByCategory')
                                  .map((item) => _amount(item, 'amountTzs'))
                                  .fold<int>(0, (a, b) => a > b ? a : b),
                            ),
                          )
                          .toList(),
                    ),
            ),
            const SizedBox(height: 12),
          ],
          if (_showOverview)
            if (_isRental) ...[
              _RecordSection(
                title: 'Monthly rent',
                records: _records('rents'),
                emptyText: 'No rent obligations recorded for this period.',
                actionLabel: 'Add rent',
                onAdd: () => _createRecord('rent'),
                amount: _amount,
                paymentType: 'rent',
                onPay: _recordPayment,
                onTenancy: _editTenancy,
                primaryValue: (item) =>
                    '${item['unitReference'] ?? 'Unit'} · ${item['billingMonth'] ?? ''}',
                secondaryValue: (item) =>
                    'Expected ${formatTzs(_amount(item, 'expectedTzs'))} · '
                    'Paid ${formatTzs(_amount(item, 'paidTzs'))} · '
                    'Due ${item['dueDate'] ?? '-'} · ${_label(item['status'] as String? ?? 'pending')}',
              ),
              const SizedBox(height: 12),
            ] else ...[
              _RecordSection(
                title: 'Confirmed booking income',
                records: _records('bookingRecords'),
                emptyText: 'No confirmed, paid bookings in this period.',
                amount: _amount,
                primaryValue: (item) =>
                    item['propertyName'] as String? ?? 'Stay booking',
                secondaryValue: (item) =>
                    '${item['date'] ?? ''} · Subtotal ${formatTzs(_amount(item, 'revenueTzs'))}',
              ),
              const SizedBox(height: 12),
            ],
          if (_showExpenses) ...[
            _RecordSection(
              title: 'Utilities & bills',
              records: _records('bills'),
              emptyText: 'No utility bills recorded for this period.',
              actionLabel: 'Add bill',
              onAdd: () => _createRecord('bill'),
              amount: _amount,
              paymentType: 'utilityBill',
              onPay: _recordPayment,
              reverseType: 'utilityBill',
              onReverse: _reverseRecord,
              primaryValue: (item) =>
                  '${_label(item['category'] as String? ?? 'other')} · ${item['provider'] ?? ''}',
              secondaryValue: (item) =>
                  'Amount ${formatTzs(_amount(item, 'amountTzs'))} · '
                  'Paid ${formatTzs(_amount(item, 'paidTzs'))} · '
                  'Due ${item['dueDate'] ?? '-'} · ${_label(item['status'] as String? ?? 'unpaid')}',
            ),
            const SizedBox(height: 12),
            _RecordSection(
              title: 'Operating expenses',
              records: _records('recentExpenses'),
              emptyText: 'No manually recorded operating expenses.',
              actionLabel: 'Add expense',
              onAdd: () => _createRecord('expense'),
              amount: _amount,
              paymentType: 'propertyExpense',
              onPay: _recordPayment,
              reverseType: 'propertyExpense',
              onReverse: _reverseRecord,
              primaryValue: (item) => item['title'] as String? ?? 'Expense',
              secondaryValue: (item) =>
                  '${_label(item['category'] as String? ?? 'other')} · '
                  '${item['propertyName'] ?? ''} · ${item['expenseDate'] ?? ''} · '
                  '${formatTzs(_amount(item, 'amountTzs'))}',
            ),
            const SizedBox(height: 12),
            _RecordSection(
              title: 'Staff payments (optional)',
              records: _records('staff'),
              emptyText: 'No staff payments recorded for this property.',
              actionLabel: 'Add staff payment',
              onAdd: () => _createRecord('staff'),
              amount: _amount,
              paymentType: 'staffObligation',
              onPay: _recordPayment,
              reverseType: 'staffObligation',
              onReverse: _reverseRecord,
              primaryValue: (item) =>
                  '${item['staffName'] ?? 'Staff'} · ${item['staffRole'] ?? ''}',
              secondaryValue: (item) =>
                  '${_label(item['frequency'] as String? ?? 'oneTime')} · '
                  'Due ${item['dueDate'] ?? '-'} · '
                  '${formatTzs(_amount(item, 'paidTzs'))} / '
                  '${formatTzs(_amount(item, 'amountTzs'))}',
            ),
            const SizedBox(height: 12),
          ],
          if (_showOverview) ...[
            _SectionCard(
              title: 'Financial alerts',
              child: _records('alerts').isEmpty
                  ? const _EmptyMessage('No unresolved financial alerts.')
                  : Column(
                      children: _records('alerts')
                          .map(
                            (alert) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                HavenIcons.notificationsActiveOutlined,
                                color: alert['severity'] == 'critical'
                                    ? HavenTheme.danger
                                    : HavenTheme.forest,
                              ),
                              title: Text(alert['title'] as String? ?? 'Alert'),
                              subtitle: Text(
                                '${(alert['property'] as Map<String, dynamic>?)?['name'] ?? ''} · '
                                '${alert['description'] ?? ''}',
                              ),
                              trailing: alert['isRead'] == true
                                  ? null
                                  : TextButton(
                                      onPressed: () =>
                                          _markAlertRead(alert['id'] as String),
                                      child: const Text('Mark read'),
                                    ),
                            ),
                          )
                          .toList(),
                    ),
            ),
            const SizedBox(height: 24),
            Text(
              _summary['incomeBasis'] as String? ?? '',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Cash flow: ${formatTzs(_amount(_summary, 'cashFlowTzs'))}. '
              '${_summary['profitBasis'] ?? ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.values,
    required this.isRental,
    required this.amount,
  });

  final Map<String, dynamic> values;
  final bool isRental;
  final int Function(Map<String, dynamic>, String) amount;

  @override
  Widget build(BuildContext context) {
    final items = isRental
        ? [
            (
              'Expected monthly rent',
              'expectedRentTzs',
              HavenIcons.receiptLong,
            ),
            ('Rent collected', 'rentCollectedTzs', HavenIcons.paymentsOutlined),
            (
              'Outstanding rent',
              'outstandingRentTzs',
              HavenIcons.pendingActions,
            ),
            ('Total expenses', 'expenseTzs', HavenIcons.trendingDown),
            ('Operating profit', 'operatingProfitTzs', HavenIcons.showChart),
            (
              'Unpaid utility bills',
              'utilityBillsOutstandingTzs',
              HavenIcons.bolt,
            ),
          ]
        : [
            ('Booking revenue', 'bookingRevenueTzs', HavenIcons.hotelOutlined),
            (
              'Verified platform receipts',
              'platformPaymentsReceivedTzs',
              HavenIcons.verifiedOutlined,
            ),
            (
              'Awaiting booking payment',
              'bookingPaymentsOutstandingTzs',
              HavenIcons.pendingActions,
            ),
            ('Operating expenses', 'expenseTzs', HavenIcons.trendingDown),
            (
              'Staff payments recorded',
              'staffPaidTzs',
              HavenIcons.peopleOutline,
            ),
            ('Operating profit', 'operatingProfitTzs', HavenIcons.showChart),
          ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: HavenMetricCard(
                    label: item.$1,
                    value: formatTzs(amount(values, item.$2)),
                    icon: item.$3,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(message, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _RecordSection extends StatelessWidget {
  const _RecordSection({
    required this.title,
    required this.records,
    required this.emptyText,
    required this.amount,
    required this.primaryValue,
    required this.secondaryValue,
    this.actionLabel,
    this.onAdd,
    this.paymentType,
    this.onPay,
    this.onTenancy,
    this.reverseType,
    this.onReverse,
  });

  final String title;
  final List<Map<String, dynamic>> records;
  final String emptyText;
  final int Function(Map<String, dynamic>, String) amount;
  final String Function(Map<String, dynamic>) primaryValue;
  final String Function(Map<String, dynamic>) secondaryValue;
  final String? actionLabel;
  final VoidCallback? onAdd;
  final String? paymentType;
  final Future<void> Function(String, Map<String, dynamic>)? onPay;
  final Future<void> Function(String, Map<String, dynamic>)? onTenancy;
  final String? reverseType;
  final Future<void> Function(String, Map<String, dynamic>)? onReverse;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (actionLabel != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(HavenIcons.add),
              label: Text(actionLabel!),
            ),
          ),
        if (records.isEmpty)
          _EmptyMessage(emptyText)
        else
          ...records.map(
            (record) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(primaryValue(record)),
              subtitle: Text(secondaryValue(record)),
              trailing: _recordActions(record),
            ),
          ),
      ],
    ),
  );

  Widget? _recordActions(Map<String, dynamic> record) {
    final canPay =
        paymentType != null &&
        record['status'] != 'paid' &&
        record['propertyId'] is String &&
        onPay != null;
    final canReverse =
        reverseType != null &&
        record['reversedAt'] == null &&
        record['propertyId'] is String &&
        onReverse != null;
    final canTenancy = onTenancy != null && record['propertyId'] is String;
    if (!canPay && !canReverse && !canTenancy) return null;
    return Wrap(
      spacing: 4,
      children: [
        if (canTenancy)
          TextButton(
            onPressed: () => onTenancy!('rent', record),
            child: const Text('Tenant'),
          ),
        if (canPay)
          TextButton(
            onPressed: () => onPay!(paymentType!, record),
            child: const Text('Record payment'),
          ),
        if (canReverse)
          PopupMenuButton<String>(
            tooltip: 'More record actions',
            onSelected: (action) {
              if (action == 'reverse') onReverse!(reverseType!, record);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'reverse', child: Text('Reverse record')),
            ],
          ),
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.label,
    required this.amountTzs,
    required this.maximum,
  });
  final String label;
  final int amountTzs;
  final int maximum;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(formatTzs(amountTzs)),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: maximum == 0 ? 0 : amountTzs / maximum,
          color: HavenTheme.forest,
          backgroundColor: HavenTheme.lightMint,
        ),
      ],
    ),
  );
}

class _IncomeExpenseChart extends StatelessWidget {
  const _IncomeExpenseChart({
    required this.trends,
    required this.amount,
    required this.isRental,
  });
  final List<Map<String, dynamic>> trends;
  final int Function(Map<String, dynamic>, String) amount;
  final bool isRental;

  @override
  Widget build(BuildContext context) {
    final rows = trends.length > 12
        ? trends.sublist(trends.length - 12)
        : trends;
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: _TrendPainter(
              income: rows.map((row) => amount(row, 'incomeTzs')).toList(),
              collected: rows
                  .map((row) => amount(row, 'collectedTzs'))
                  .toList(),
              expenses: rows.map((row) => amount(row, 'expenseTzs')).toList(),
              profit: rows
                  .map((row) => amount(row, 'operatingProfitTzs'))
                  .toList(),
              incomeColor: HavenTheme.forest,
              expenseColor: Colors.orange.shade700,
              profitColor: Colors.blue.shade700,
              isRental: isRental,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: [
            _Legend(
              color: HavenTheme.forest,
              label: isRental ? 'Expected rent' : 'Booking revenue',
            ),
            if (isRental)
              _Legend(color: Colors.teal.shade400, label: 'Rent collected'),
            _Legend(color: Colors.orange.shade700, label: 'Expenses'),
            _Legend(color: Colors.blue.shade700, label: 'Operating profit'),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: rows
              .map(
                (row) => Text(
                  (row['month'] as String? ?? '').substring(5),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.income,
    required this.collected,
    required this.expenses,
    required this.profit,
    required this.incomeColor,
    required this.expenseColor,
    required this.profitColor,
    required this.isRental,
  });
  final List<int> income;
  final List<int> collected;
  final List<int> expenses;
  final List<int> profit;
  final Color incomeColor;
  final Color expenseColor;
  final Color profitColor;
  final bool isRental;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [
      ...income,
      ...collected,
      ...expenses,
      ...profit.map((v) => v.abs()),
    ];
    final maximum = values.isEmpty
        ? 1.0
        : values
              .fold<int>(0, (a, b) => a > b ? a : b)
              .toDouble()
              .clamp(1, double.infinity);
    final baseline = size.height / 2;
    final gap = size.width / (income.length + 1);
    final barWidth = (gap * 0.24).clamp(3, 18).toDouble();
    final axis = Paint()
      ..color = HavenTheme.lightMint
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, baseline), Offset(size.width, baseline), axis);
    final incomePaint = Paint()..color = incomeColor;
    final collectedPaint = Paint()..color = Colors.teal.shade400;
    final expensePaint = Paint()..color = expenseColor;
    final profitPaint = Paint()
      ..color = profitColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final profitPath = Path();
    for (var index = 0; index < income.length; index++) {
      final x = gap * (index + 1);
      final incomeHeight = income[index] / maximum * baseline;
      final expenseHeight = expenses[index] / maximum * baseline;
      final bars = isRental
          ? [
              (x - barWidth * 1.5, incomeHeight, incomePaint),
              (
                x - barWidth / 2,
                collected[index] / maximum * baseline,
                collectedPaint,
              ),
              (x + barWidth / 2, expenseHeight, expensePaint),
            ]
          : [
              (x - barWidth, incomeHeight, incomePaint),
              (x + 2, expenseHeight, expensePaint),
            ];
      for (final (left, height, paint) in bars) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, baseline - height, barWidth, height),
            const Radius.circular(3),
          ),
          paint,
        );
      }
      final y = baseline - profit[index] / maximum * baseline;
      if (index == 0) {
        profitPath.moveTo(x, y);
      } else {
        profitPath.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = profitColor);
    }
    canvas.drawPath(profitPath, profitPaint);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.income != income ||
      oldDelegate.collected != collected ||
      oldDelegate.expenses != expenses ||
      oldDelegate.profit != profit ||
      oldDelegate.isRental != isRental;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
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

class _FinancialRecordDialog extends StatefulWidget {
  const _FinancialRecordDialog({required this.type});
  final String type;

  @override
  State<_FinancialRecordDialog> createState() => _FinancialRecordDialogState();
}

class _FinancialRecordDialogState extends State<_FinancialRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _second = TextEditingController();
  final _amount = TextEditingController();
  final _date = TextEditingController();
  String _category = 'other';
  String _frequency = 'monthly';
  String _month = _monthNow();
  bool _recurring = false;

  static String _monthNow() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    _amount.dispose();
    _date.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    final rent = type == 'rent';
    final bill = type == 'bill';
    final staff = type == 'staff';
    final title = rent
        ? 'Add rent obligation'
        : bill
        ? 'Add utility bill'
        : staff
        ? 'Add staff payment'
        : 'Add expense';
    final categories = bill
        ? const [
            'electricity',
            'water',
            'internet',
            'tv',
            'streaming',
            'gas',
            'waste',
            'security',
            'serviceCharge',
            'other',
          ]
        : const [
            'maintenance',
            'cleaning',
            'security',
            'supplies',
            'administration',
            'other',
          ];
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (rent)
                  TextFormField(
                    controller: _first,
                    decoration: const InputDecoration(
                      labelText: 'Unit number / reference',
                    ),
                    validator: _required,
                  )
                else if (staff)
                  TextFormField(
                    controller: _first,
                    decoration: const InputDecoration(
                      labelText: 'Staff member name',
                    ),
                    validator: _required,
                  )
                else if (bill)
                  TextFormField(
                    controller: _first,
                    decoration: const InputDecoration(
                      labelText: 'Service provider',
                    ),
                    validator: _required,
                  )
                else
                  TextFormField(
                    controller: _first,
                    decoration: const InputDecoration(
                      labelText: 'Expense title',
                    ),
                    validator: _required,
                  ),
                if (rent)
                  TextFormField(
                    controller: _second,
                    decoration: const InputDecoration(
                      labelText: 'Tenant reference (optional)',
                    ),
                  ),
                if (staff)
                  TextFormField(
                    controller: _second,
                    decoration: const InputDecoration(labelText: 'Staff role'),
                    validator: _required,
                  ),
                if (bill || !rent && !staff)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _category,
                    decoration: InputDecoration(
                      labelText: bill ? 'Bill category' : 'Expense category',
                    ),
                    items: categories
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(_label(item)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _category = value ?? 'other'),
                  ),
                if (staff)
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _frequency,
                    decoration: const InputDecoration(
                      labelText: 'Payment frequency',
                    ),
                    items: const ['monthly', 'weekly', 'daily', 'oneTime']
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(_label(item)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _frequency = value ?? 'monthly'),
                  ),
                TextFormField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: rent ? 'Expected rent (TZS)' : 'Amount (TZS)',
                  ),
                  validator: (value) {
                    final amount = int.tryParse(value ?? '');
                    return amount == null || amount < 1
                        ? 'Enter a positive whole amount.'
                        : null;
                  },
                ),
                if (rent || bill)
                  TextFormField(
                    initialValue: _month,
                    decoration: InputDecoration(
                      labelText: rent
                          ? 'Billing month (YYYY-MM)'
                          : 'Billing month (YYYY-MM)',
                    ),
                    onChanged: (value) => _month = value,
                    validator: (value) =>
                        RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(value ?? '')
                        ? null
                        : 'Use YYYY-MM.',
                  ),
                TextFormField(
                  controller: _date,
                  decoration: InputDecoration(
                    labelText: rent || bill || staff
                        ? 'Due date (YYYY-MM-DD)'
                        : 'Expense date (YYYY-MM-DD)',
                    hintText: 'YYYY-MM-DD',
                  ),
                  validator: (value) => _validDate(value ?? '')
                      ? null
                      : 'Enter a valid YYYY-MM-DD date.',
                ),
                if (bill)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Recurring monthly bill'),
                    value: _recurring,
                    onChanged: (value) => setState(() => _recurring = value),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            final amount = int.parse(_amount.text);
            final common = <String, Object?>{'amountTzs': amount};
            final date = _date.text.trim();
            if (rent) {
              Navigator.pop(context, {
                'unitReference': _first.text.trim(),
                'tenantReference': _second.text.trim().isEmpty
                    ? null
                    : _second.text.trim(),
                'billingMonth': _month,
                'expectedTzs': amount,
                'dueDate': date,
              });
            } else if (bill) {
              Navigator.pop(context, {
                'provider': _first.text.trim(),
                'category': _category,
                'billingMonth': _month,
                ...common,
                'dueDate': date,
                'recurring': _recurring,
              });
            } else if (staff) {
              Navigator.pop(context, {
                'staffName': _first.text.trim(),
                'staffRole': _second.text.trim(),
                'frequency': _frequency,
                ...common,
                'dueDate': date,
              });
            } else {
              Navigator.pop(context, {
                'title': _first.text.trim(),
                'category': _category,
                ...common,
                'expenseDate': date,
              });
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog();

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _controller = TextEditingController();
  final _method = TextEditingController();
  final _reference = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    _method.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record offline payment'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Amount received / paid (TZS)',
          ),
        ),
        TextField(
          controller: _method,
          decoration: const InputDecoration(
            labelText: 'Payment method (optional)',
          ),
        ),
        TextField(
          controller: _reference,
          decoration: const InputDecoration(
            labelText: 'Receipt / reference (optional)',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final amount = int.tryParse(_controller.text);
          if (amount == null || amount < 1) return;
          Navigator.pop(context, {
            'amountTzs': amount,
            if (_method.text.trim().isNotEmpty) 'method': _method.text.trim(),
            if (_reference.text.trim().isNotEmpty)
              'reference': _reference.text.trim(),
          });
        },
        child: const Text('Record payment'),
      ),
    ],
  );
}

String? _required(String? value) =>
    value == null || value.trim().length < 2 ? 'This field is required.' : null;

bool _validDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}

String _label(String value) => value
    .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match[1]}')
    .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match[1]} ${match[2]}',
    )
    .replaceAll('_', ' ')
    .split(RegExp(r'\s+'))
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
