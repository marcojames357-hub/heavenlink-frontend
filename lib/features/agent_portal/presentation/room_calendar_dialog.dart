import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';
import 'package:intl/intl.dart';

import '../domain/agent_models.dart';
import '../state/agent_portal_store.dart';

class RoomCalendarDialog extends StatelessWidget {
  const RoomCalendarDialog({
    required this.store,
    required this.propertyId,
    super.key,
  });

  final AgentPortalStore store;
  final String propertyId;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Room availability calendar'),
    content: SizedBox(
      width: 720,
      height: 530,
      child: RoomCalendarPanel(store: store, propertyId: propertyId),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

/// The room-by-date availability grid, usable inline or inside a dialog.
class RoomCalendarPanel extends StatefulWidget {
  const RoomCalendarPanel({
    required this.store,
    required this.propertyId,
    super.key,
  });

  final AgentPortalStore store;
  final String propertyId;

  @override
  State<RoomCalendarPanel> createState() => _RoomCalendarPanelState();
}

class _RoomCalendarPanelState extends State<RoomCalendarPanel> {
  late DateTimeRange _range;
  List<RoomCalendarEntry> _rooms = [];
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _range = DateTimeRange(
      start: today,
      end: today.add(const Duration(days: 6)),
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rooms = await widget.store.loadRoomCalendar(
        widget.propertyId,
        _range.start,
        _range.end.add(const Duration(days: 1)),
      );
      if (mounted) setState(() => _rooms = rooms);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chooseDates() async {
    final range = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (range == null || !mounted) return;
    if (range.end.difference(range.start).inDays >= 93) {
      setState(() => _error = 'Choose a range of up to 93 days.');
      return;
    }
    setState(() => _range = range);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd MMM yyyy');
    final rooms = _rooms
        .where(
          (room) =>
              room.roomNumber.toLowerCase().contains(_search.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _loading ? null : _chooseDates,
              icon: const Icon(HavenIcons.dateRange),
              label: Text(
                '${date.format(_range.start)} – ${date.format(_range.end)}',
              ),
            ),
            IconButton(
              tooltip: 'Refresh calendar',
              onPressed: _loading ? null : _load,
              icon: const Icon(HavenIcons.refresh),
            ),
          ],
        ),
        const Text(
          'Dates use UTC; checkout and block end dates are exclusive. Walk-in occupancy is shown separately from reservations.',
        ),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search room identifier',
            prefixIcon: Icon(HavenIcons.search),
          ),
          onChanged: (value) => setState(() => _search = value),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : rooms.isEmpty
              ? const Center(child: Text('No rooms match this search.'))
              : ListView.builder(
                  itemCount: rooms.length,
                  itemBuilder: (context, index) {
                    final room = rooms[index];
                    return Card(
                      child: ExpansionTile(
                        title: Text(
                          'Room ${room.roomNumber} · ${room.category ?? 'Unassigned'}',
                        ),
                        subtitle: Text(
                          [
                            if (room.floor != null) room.floor!,
                            room.occupancy == 'checkedIn'
                                ? 'Checked in (walk-in)'
                                : 'No walk-in checked in',
                            if (room.status != 'active') 'Out of service',
                            if (room.status == 'active' && room.events.isEmpty)
                              room.category == null
                                  ? 'Unassigned'
                                  : 'Available for selected dates',
                          ].join(' · '),
                        ),
                        children: [
                          for (final event in room.events)
                            ListTile(
                              dense: true,
                              title: Text(switch (event.kind) {
                                'online' => 'Online reserved',
                                'hold' => 'Temporarily held',
                                'walkIn' =>
                                  event.overdue
                                      ? 'Walk-in · overdue checkout'
                                      : 'Walk-in reserved / occupied',
                                'blocked' => 'Blocked',
                                _ => event.kind,
                              }),
                              subtitle: Text(
                                '${date.format(event.start.toUtc())} – ${date.format(event.end.toUtc())}'
                                '${event.guestName == null ? '' : ' · ${event.guestName}'}'
                                '${event.reason == null ? '' : ' · ${event.reason}'}',
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
