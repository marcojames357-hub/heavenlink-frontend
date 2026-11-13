import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show ShadButton;

import '../domain/agent_models.dart';
import '../state/agent_portal_store.dart';

class WalkInDialog extends StatefulWidget {
  const WalkInDialog({
    required this.store,
    required this.propertyId,
    required this.rooms,
    this.initialRoomId,
    super.key,
  });

  final AgentPortalStore store;
  final String propertyId;
  final List<PhysicalRoom> rooms;
  final String? initialRoomId;

  @override
  State<WalkInDialog> createState() => _WalkInDialogState();
}

class _WalkInDialogState extends State<WalkInDialog> {
  List<WalkInReservation> _stays = [];
  bool _loading = true;
  String? _error;

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
      final stays = await widget.store.loadWalkIns(widget.propertyId);
      if (mounted) setState(() => _stays = stays);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _WalkInForm(
        store: widget.store,
        propertyId: widget.propertyId,
        rooms: widget.rooms,
        initialRoomId: widget.initialRoomId,
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _action(WalkInReservation stay, String action) async {
    final values = <String, Object?>{};
    if (action == 'cancel') {
      final reason = await _askText(
        'Cancel walk-in',
        'Reason for cancellation',
      );
      if (reason == null) return;
      values['reason'] = reason;
    } else if (action == 'payment') {
      final status = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Record payment status'),
          children: [
            for (final status in ['unpaid', 'partiallyPaid', 'paid'])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, status),
                child: Text(_paymentLabel(status)),
              ),
          ],
        ),
      );
      if (status == null) return;
      values['paymentStatus'] = status;
    } else if (action == 'extend') {
      final next = await _pickDateTime(
        context,
        stay.checkOut.add(const Duration(days: 1)),
      );
      if (next == null) return;
      values['checkOut'] = next.toUtc().toIso8601String();
    } else if (action == 'change-room') {
      final current = widget.rooms
          .where((room) => room.id == stay.roomId)
          .firstOrNull;
      final alternatives = widget.rooms
          .where(
            (room) =>
                room.id != stay.roomId &&
                room.status == 'active' &&
                room.roomTypeId != null &&
                room.roomTypeId == current?.roomTypeId,
          )
          .toList();
      if (alternatives.isEmpty) {
        if (mounted) {
          setState(() => _error = 'No other active rooms in this category.');
        }
        return;
      }
      final roomId = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose replacement room'),
          children: [
            for (final room in alternatives)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, room.id),
                child: Text('Room ${room.roomNumber}'),
              ),
          ],
        ),
      );
      if (roomId == null) return;
      values['roomId'] = roomId;
      final reason = await _askText('Change room', 'Reason for changing rooms');
      if (reason == null) return;
      values['reason'] = reason;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            action == 'checkout' ? 'Record checkout?' : 'Record check-in?',
          ),
          content: Text('Confirm for ${stay.guestName}.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.store.updateWalkIn(
        widget.propertyId,
        stay.id,
        action,
        values,
      );
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<String?> _askText(String title, String label) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: label),
            maxLength: 500,
            onChanged: (_) => setDialogState(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: controller.text.trim().length >= 3
                  ? () => Navigator.pop(context, controller.text.trim())
                  : null,
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd MMM yyyy, HH:mm');
    return AlertDialog(
      title: Row(
        children: [
          _DialogIcon(icon: LucideIcons.doorOpen),
          const SizedBox(width: 12),
          const Expanded(child: Text('Walk-in reservations')),
        ],
      ),
      content: SizedBox(
        width: 650,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.62,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manage on-site stays, room assignments, and payment status.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _InlineError(message: _error!),
              ],
              const SizedBox(height: 12),
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_stays.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.calendarDays,
                          size: 32,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No walk-in reservations yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'New stays recorded here will appear in this list.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _stays.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final stay = _stays[index];
                      final room = widget.rooms
                          .where((room) => room.id == stay.roomId)
                          .firstOrNull;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      stay.guestName,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Room ${room?.roomNumber ?? 'unknown'} · TZS ${NumberFormat('#,##0').format(stay.priceTzs)}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${formatter.format(stay.checkIn)} – ${formatter.format(stay.checkOut)}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        _StatusBadge(
                                          label: _statusLabel(stay.status),
                                          icon: LucideIcons.badgeCheck,
                                        ),
                                        _StatusBadge(
                                          label: _paymentLabel(
                                            stay.paymentStatus,
                                          ),
                                          icon: LucideIcons.wallet,
                                          subdued: true,
                                        ),
                                      ],
                                    ),
                                    if (stay.roomSegments.length > 1)
                                      TextButton.icon(
                                        onPressed: () => showDialog<void>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text(
                                              'Room assignment history',
                                            ),
                                            content: SizedBox(
                                              width: 420,
                                              child: ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                      maxHeight: 360,
                                                    ),
                                                child: ListView(
                                                  shrinkWrap: true,
                                                  children: [
                                                    for (final segment
                                                        in stay.roomSegments)
                                                      ListTile(
                                                        leading: const Icon(
                                                          LucideIcons.bedDouble,
                                                        ),
                                                        title: Text(
                                                          'Room ${segment.roomNumber}',
                                                        ),
                                                        subtitle: Text(
                                                          '${formatter.format(segment.startAt)} – ${formatter.format(segment.endAt)}',
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text('Close'),
                                              ),
                                            ],
                                          ),
                                        ),
                                        icon: const Icon(
                                          LucideIcons.history,
                                          size: 16,
                                        ),
                                        label: const Text('Room history'),
                                      ),
                                  ],
                                ),
                              ),
                              if ([
                                'reserved',
                                'checkedIn',
                              ].contains(stay.status))
                                PopupMenuButton<String>(
                                  tooltip: 'Manage walk-in',
                                  onSelected: (action) => _action(stay, action),
                                  itemBuilder: (_) => [
                                    if (stay.status == 'reserved')
                                      const PopupMenuItem(
                                        value: 'check-in',
                                        child: Text('Record check-in'),
                                      ),
                                    if (stay.status == 'checkedIn')
                                      const PopupMenuItem(
                                        value: 'checkout',
                                        child: Text('Record checkout'),
                                      ),
                                    const PopupMenuItem(
                                      value: 'extend',
                                      child: Text('Extend stay'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'change-room',
                                      child: Text('Change room'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'payment',
                                      child: Text('Update payment status'),
                                    ),
                                    if (stay.status == 'reserved')
                                      const PopupMenuItem(
                                        value: 'cancel',
                                        child: Text('Cancel reservation'),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        OutlinedButton(
          onPressed: _loading ? null : _load,
          child: const Icon(LucideIcons.refreshCw, size: 18),
        ),
        ShadButton(
          onPressed: _loading ? null : _create,
          enabled: !_loading,
          leading: const Icon(LucideIcons.plus, size: 18),
          child: const Text('Record walk-in'),
        ),
      ],
    );
  }
}

String _paymentLabel(String status) => switch (status) {
  'partiallyPaid' => 'Partially paid',
  'paid' => 'Paid',
  _ => 'Unpaid',
};

String _statusLabel(String status) => switch (status) {
  'checkedIn' => 'Checked in',
  'completed' => 'Checked out',
  'cancelled' => 'Cancelled',
  _ => 'Reserved',
};

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final first = DateUtils.dateOnly(
    DateTime.now().subtract(const Duration(days: 1)),
  );
  final date = await showDatePicker(
    context: context,
    initialDate: initial.isBefore(first) ? first : initial,
    firstDate: first,
    lastDate: DateTime(2100),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

class _WalkInForm extends StatefulWidget {
  const _WalkInForm({
    required this.store,
    required this.propertyId,
    required this.rooms,
    this.initialRoomId,
  });
  final AgentPortalStore store;
  final String propertyId;
  final List<PhysicalRoom> rooms;
  final String? initialRoomId;

  @override
  State<_WalkInForm> createState() => _WalkInFormState();
}

class _WalkInFormState extends State<_WalkInForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _price = TextEditingController();
  final _notes = TextEditingController();
  final _requestKey = List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String? _roomId;
  String _payment = 'unpaid';
  bool _checkInNow = true;
  bool _saving = false;
  String? _error;
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now().add(const Duration(days: 1));

  List<PhysicalRoom> get _eligible => widget.rooms
      .where((room) => room.status == 'active' && room.roomTypeId != null)
      .toList();

  @override
  void initState() {
    super.initState();
    _roomId = _eligible.any((room) => room.id == widget.initialRoomId)
        ? widget.initialRoomId
        : _eligible.firstOrNull?.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _roomId == null) return;
    if (!_end.isAfter(_start)) {
      setState(() => _error = 'Checkout must be after check-in.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.createWalkIn(widget.propertyId, {
        'requestKey': _requestKey,
        'roomId': _roomId,
        'guestName': _name.text.trim(),
        'guestPhone': _phone.text.trim(),
        'checkIn': _start.toUtc().toIso8601String(),
        'checkOut': _end.toUtc().toIso8601String(),
        'priceTzs': int.parse(_price.text),
        'paymentStatus': _payment,
        'notes': _notes.text.trim(),
        'checkInNow': _checkInNow,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('dd MMM yyyy, HH:mm');
    return AlertDialog(
      title: Row(
        children: [
          _DialogIcon(icon: LucideIcons.userRoundPlus),
          const SizedBox(width: 12),
          const Expanded(child: Text('Record walk-in')),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.62,
          ),
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Add guest details and confirm the stay terms.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _roomId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Room',
                      prefixIcon: Icon(LucideIcons.bedDouble),
                    ),
                    items: _eligible
                        .map(
                          (room) => DropdownMenuItem(
                            value: room.id,
                            child: Text(
                              '${room.roomNumber} · ${room.roomTypeName ?? 'Category'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _roomId = value),
                    validator: (value) => value == null
                        ? 'Assign an active room category first.'
                        : null,
                  ),
                  TextFormField(
                    controller: _name,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Guest name',
                      prefixIcon: Icon(LucideIcons.userRound),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 2
                        ? 'Enter a guest name.'
                        : null,
                  ),
                  TextFormField(
                    controller: _phone,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: 'Contact (optional)',
                      prefixIcon: Icon(LucideIcons.phone),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _DateTimeField(
                    label: 'Check-in',
                    value: format.format(_start),
                    enabled: !_saving,
                    onTap: () async {
                      final date = await _pickDateTime(context, _start);
                      if (date != null) setState(() => _start = date);
                    },
                  ),
                  const SizedBox(height: 8),
                  _DateTimeField(
                    label: 'Expected checkout',
                    value: format.format(_end),
                    enabled: !_saving,
                    onTap: () async {
                      final date = await _pickDateTime(context, _end);
                      if (date != null) setState(() => _end = date);
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Guest is checking in now'),
                    value: _checkInNow,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _checkInNow = value),
                  ),
                  TextFormField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Agreed total (TZS)',
                      prefixIcon: Icon(LucideIcons.circleDollarSign),
                    ),
                    validator: (value) {
                      final amount = int.tryParse(value ?? '');
                      return amount == null || amount < 0 || amount > 2000000000
                          ? 'Enter a valid whole amount.'
                          : null;
                    },
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _payment,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Payment status',
                    ),
                    items: ['unpaid', 'partiallyPaid', 'paid']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(_paymentLabel(value)),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _payment = value!),
                  ),
                  TextFormField(
                    controller: _notes,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      prefixIcon: Icon(LucideIcons.notebookPen),
                    ),
                    maxLines: 2,
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _InlineError(message: _error!),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Back'),
        ),
        ShadButton(
          onPressed: _saving ? null : _save,
          enabled: !_saving,
          leading: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.save, size: 16),
          child: Text(_saving ? 'Saving' : 'Save walk-in'),
        ),
      ],
    );
  }
}

class _DialogIcon extends StatelessWidget {
  const _DialogIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: colors.onPrimaryContainer, size: 21),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.icon,
    this.subdued = false,
  });

  final String label;
  final IconData icon;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = subdued
        ? colors.surfaceContainerHigh
        : colors.tertiaryContainer;
    final foreground = subdued
        ? colors.onSurfaceVariant
        : colors.onTertiaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.circleAlert,
            size: 18,
            color: colors.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(LucideIcons.calendarClock, color: colors.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 2),
                    Text(value, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                color: colors.onSurfaceVariant,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
