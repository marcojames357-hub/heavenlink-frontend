import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';

/// Collects tenancy changes for one rent record. Returns the request body,
/// containing only the fields the agent chose to change.
Future<Map<String, Object?>?> showTenancyDialog(BuildContext context) =>
    showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => const _TenancyDialog(),
    );

enum _TenantAction { keep, link, unlink }

class _TenancyDialog extends StatefulWidget {
  const _TenancyDialog();

  @override
  State<_TenancyDialog> createState() => _TenancyDialogState();
}

class _TenancyDialogState extends State<_TenancyDialog> {
  final _phone = TextEditingController();
  final _leaseEnd = TextEditingController();
  final _offsets = TextEditingController();
  _TenantAction _action = _TenantAction.keep;
  bool _endTenancy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _leaseEnd.dispose();
    _offsets.dispose();
    super.dispose();
  }

  void _submit() {
    final body = <String, Object?>{};
    if (_action == _TenantAction.link) {
      final phone = _phone.text.trim();
      if (!RegExp(r'^\+255\d{9}$').hasMatch(phone)) {
        setState(() => _error = 'Enter the tenant phone as +255XXXXXXXXX.');
        return;
      }
      body['tenantPhone'] = phone;
    } else if (_action == _TenantAction.unlink) {
      body['unlinkTenant'] = true;
    }
    final lease = _leaseEnd.text.trim();
    if (lease.isNotEmpty) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(lease)) {
        setState(() => _error = 'Lease end must look like 2026-12-31.');
        return;
      }
      body['leaseEndDate'] = lease;
    }
    final rawOffsets = _offsets.text.trim();
    if (rawOffsets.isNotEmpty) {
      final values = rawOffsets.split(',').map((e) => int.tryParse(e.trim()));
      if (values.any((v) => v == null || v < -30 || v > 30) ||
          values.length > 6) {
        setState(
          () =>
              _error = 'Use up to 6 whole days between -30 and 30, e.g. -3,0.',
        );
        return;
      }
      body['reminderOffsets'] = values.cast<int>().toList();
    }
    if (_endTenancy) body['endTenancy'] = true;
    if (body.isEmpty) {
      setState(() => _error = 'Change at least one setting.');
      return;
    }
    Navigator.of(context).pop(body);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Tenant & reminders')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<_TenantAction>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: _TenantAction.keep,
                  label: Text(context.tr('Keep')),
                ),
                ButtonSegment(
                  value: _TenantAction.link,
                  label: Text(context.tr('Link')),
                ),
                ButtonSegment(
                  value: _TenantAction.unlink,
                  label: Text(context.tr('Unlink')),
                ),
              ],
              selected: {_action},
              onSelectionChanged: (value) =>
                  setState(() => _action = value.first),
            ),
            if (_action == _TenantAction.link) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: context.tr('Tenant phone'),
                  helperText: context.tr(
                    'Must match a verified Haven Link customer account.',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _offsets,
              decoration: InputDecoration(
                labelText: context.tr('Reminder days (optional)'),
                helperText: context.tr(
                  'Days from the due date, e.g. -3,0 (negative = before).',
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _leaseEnd,
              decoration: InputDecoration(
                labelText: context.tr('Lease end date (optional)'),
                hintText: 'YYYY-MM-DD',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('End tenancy')),
              value: _endTenancy,
              onChanged: (value) => setState(() => _endTenancy = value),
            ),
            if (_error != null)
              Text(
                context.tr(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(onPressed: _submit, child: Text(context.tr('Save'))),
      ],
    );
  }
}
