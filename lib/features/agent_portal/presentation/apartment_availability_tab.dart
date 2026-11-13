import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/data/api_client.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../properties/domain/property.dart';

class _Block {
  const _Block(this.id, this.start, this.end, this.reason);

  final String id;
  final String start;
  final String end;
  final String reason;
}

/// Apartment workspace: block and release dates for whole-unit apartments.
/// Customer reservations and holds are enforced by the server.
class ApartmentAvailabilityTab extends StatefulWidget {
  const ApartmentAvailabilityTab({
    required this.listings,
    required this.tokenProvider,
    super.key,
  });

  final List<Property> listings;
  final String? Function() tokenProvider;

  @override
  State<ApartmentAvailabilityTab> createState() =>
      _ApartmentAvailabilityTabState();
}

class _ApartmentAvailabilityTabState extends State<ApartmentAvailabilityTab> {
  late final ApiClient _api = ApiClient(tokenProvider: widget.tokenProvider);
  String? _propertyId;
  List<_Block> _blocks = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.listings.isNotEmpty) {
      _propertyId = widget.listings.first.id;
      _load();
    }
  }

  String get _base => '/api/v1/agents/apartments/$_propertyId/blocks';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.get(_base);
      final blocks = (result['blocks'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (json) => _Block(
              json['id'] as String,
              (json['startDate'] as String).substring(0, 10),
              (json['endDate'] as String).substring(0, 10),
              json['reason'] as String? ?? '',
            ),
          )
          .toList();
      if (mounted) setState(() => _blocks = blocks);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _day(DateTime date) => date.toIso8601String().substring(0, 10);

  Future<void> _addBlock() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 730)),
      helpText: context.tr('Choose dates to block'),
    );
    if (range == null || !mounted) return;
    final reason = await _askReason();
    if (reason == null) return;
    try {
      // The server treats the end date as the (exclusive) release day.
      await _api.post(_base, {
        'startDate': _day(range.start),
        'endDate': _day(range.end.add(const Duration(days: 1))),
        'reason': reason,
      });
      await _load();
    } on StateError catch (error) {
      _toast(error.message);
    }
  }

  Future<String?> _askReason() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('Reason for blocking')),
        content: TextField(
          controller: controller,
          maxLength: 500,
          decoration: InputDecoration(
            hintText: context.tr('Maintenance, personal use…'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(context.tr('Block dates')),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason == null || reason.length < 2 ? null : reason;
  }

  Future<void> _remove(_Block block) async {
    try {
      await _api.delete('$_base/${block.id}');
      await _load();
    } on StateError catch (error) {
      _toast(error.message);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.listings.isEmpty) {
      return Center(
        child: Text(context.tr('Add an apartment to manage its availability.')),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _propertyId,
          decoration: InputDecoration(labelText: context.tr('Apartment')),
          items: [
            for (final property in widget.listings)
              DropdownMenuItem(value: property.id, child: Text(property.name)),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _propertyId = value);
            _load();
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('Blocked dates'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            FilledButton.icon(
              onPressed: _addBlock,
              icon: const Icon(HavenIcons.eventBusyOutlined),
              label: Text(context.tr('Block dates')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
        if (!_loading && _error == null && _blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              context.tr('No blocked dates. Guests can book any free night.'),
              style: const TextStyle(color: HavenTheme.muted),
            ),
          ),
        for (final block in _blocks)
          Card(
            child: ListTile(
              leading: const Icon(
                HavenIcons.eventBusyOutlined,
                color: HavenTheme.teal,
              ),
              title: Text('${block.start} → ${block.end}'),
              subtitle: Text(block.reason),
              trailing: IconButton(
                tooltip: context.tr('Release dates'),
                icon: const Icon(HavenIcons.deleteOutline),
                onPressed: () => _remove(block),
              ),
            ),
          ),
      ],
    );
  }
}
