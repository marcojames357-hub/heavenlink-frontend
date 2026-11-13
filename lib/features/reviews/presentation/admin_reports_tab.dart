import 'package:flutter/material.dart';

import '../data/review_repository.dart';
import '../domain/review_models.dart';

/// Admin: private problem reports with triage, notes and escalation.
class AdminReportsTab extends StatefulWidget {
  const AdminReportsTab({
    required this.tokenProvider,
    this.repository,
    super.key,
  });

  final String? Function() tokenProvider;
  final ReviewRepository? repository;

  @override
  State<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends State<AdminReportsTab> {
  late final ReviewRepository _repository;
  late Future<({List<ProblemReportItem> reports, Map<String, int> stats})>
  _data;
  String? _category;
  String? _severity;
  String? _status;

  @override
  void initState() {
    super.initState();
    _repository =
        widget.repository ??
        ReviewRepository(tokenProvider: widget.tokenProvider);
    _load();
  }

  void _load() {
    _data = _repository.loadAdminReports(
      category: _category,
      severity: _severity,
      status: _status,
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(_load);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    }
  }

  Future<void> _note(ProblemReportItem report) async {
    final controller = TextEditingController();
    var visibility = 'internal';
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Add note'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: visibility,
                decoration: const InputDecoration(labelText: 'Visible to'),
                items: [
                  const DropdownMenuItem(
                    value: 'internal',
                    child: Text('Internal only'),
                  ),
                  const DropdownMenuItem(
                    value: 'customer',
                    child: Text('Customer'),
                  ),
                  if (report.sharedWithAgent)
                    const DropdownMenuItem(
                      value: 'agent',
                      child: Text('Stays Agent'),
                    ),
                ],
                onChanged: (value) =>
                    setLocal(() => visibility = value ?? 'internal'),
              ),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 6,
                maxLength: 2000,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, (controller.text.trim(), visibility)),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result == null || result.$1.length < 2) return;
    await _run(
      () => _repository.addAdminReportNote(report.id, result.$1, result.$2),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _data,
    builder: (context, snapshot) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String?>(
                value: _category,
                hint: const Text('Category'),
                onChanged: (value) => setState(() {
                  _category = value;
                  _load();
                }),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All categories'),
                  ),
                  for (final entry in problemCategories.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
              ),
              DropdownButton<String?>(
                value: _severity,
                hint: const Text('Urgency'),
                onChanged: (value) => setState(() {
                  _severity = value;
                  _load();
                }),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Any urgency')),
                  DropdownMenuItem(value: 'general', child: Text('General')),
                  DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                ],
              ),
              DropdownButton<String?>(
                value: _status,
                hint: const Text('Status'),
                onChanged: (value) => setState(() {
                  _status = value;
                  _load();
                }),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Any status'),
                  ),
                  for (final entry in reportStatusLabels.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
              ),
            ],
          ),
          if (snapshot.connectionState == ConnectionState.waiting)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (snapshot.hasError)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Reports could not be loaded.'),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Open ${snapshot.data!.stats['open'] ?? 0} · Urgent ${snapshot.data!.stats['urgent'] ?? 0} · Sensitive ${snapshot.data!.stats['sensitive'] ?? 0}',
              ),
            ),
            if (snapshot.data!.reports.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No problem reports match.'),
              ),
            for (final report in snapshot.data!.reports) _card(report),
          ],
        ],
      );
    },
  );

  Widget _card(ProblemReportItem report) => Card(
    child: ExpansionTile(
      title: Text(
        '${report.reference} · ${problemCategories[report.category] ?? report.category}',
      ),
      subtitle: Text(
        '${report.propertyName} · ${report.severity == 'urgent' ? 'URGENT · ' : ''}${report.classification == 'sensitive' ? 'SENSITIVE · ' : ''}${reportStatusLabels[report.status] ?? report.status}',
      ),
      childrenPadding: const EdgeInsets.all(12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.customerName != null)
          Text('Customer: ${report.customerName}'),
        Text('Booking: ${report.bookingId}'),
        const SizedBox(height: 6),
        Text(report.description),
        if (report.evidence.isNotEmpty)
          Text('Evidence files: ${report.evidence.length}'),
        for (final note in report.notes)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '[${note.visibility}] ${note.authorRole}: ${note.body}',
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<String>(
              value: report.status,
              onChanged: (value) => value == null
                  ? null
                  : _run(
                      () => _repository.updateAdminReport(
                        report.id,
                        status: value,
                      ),
                    ),
              items: [
                for (final entry in reportStatusLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
            ),
            if (report.severity != 'urgent')
              OutlinedButton(
                onPressed: () => _run(
                  () =>
                      _repository.updateAdminReport(report.id, escalate: true),
                ),
                child: const Text('Escalate'),
              ),
            FilterChip(
              label: const Text('Share with agent'),
              selected: report.sharedWithAgent,
              onSelected: (value) => _run(
                () => _repository.updateAdminReport(
                  report.id,
                  sharedWithAgent: value,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _note(report),
              child: const Text('Add note'),
            ),
          ],
        ),
      ],
    ),
  );
}
