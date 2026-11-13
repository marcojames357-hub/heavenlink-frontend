import 'package:flutter/material.dart';
import 'package:haven_link/core/theme/haven_icons.dart';

import '../../../core/formatters/currency_formatter.dart';
import '../../properties/domain/property.dart';
import '../domain/agent_models.dart';
import '../state/agent_portal_store.dart';
import 'walk_in_dialog.dart';
import 'room_calendar_dialog.dart';

/// Which part of room inventory a sidebar entry shows.
enum RoomInventoryView { all, categories, rooms, calendar }

class RoomInventoryTab extends StatefulWidget {
  const RoomInventoryTab({
    required this.agentStore,
    this.view = RoomInventoryView.all,
    super.key,
  });

  final AgentPortalStore agentStore;
  final RoomInventoryView view;

  @override
  State<RoomInventoryTab> createState() => _RoomInventoryTabState();
}

class _RoomInventoryTabState extends State<RoomInventoryTab> {
  String? _propertyId;
  String? _floor;
  String? _roomTypeId;
  String? _categoryFilter;
  String _roomSearch = '';
  int _page = 0;
  static const _pageSize = 25;
  Set<String> _selectedRoomIds = {};
  List<PhysicalRoom> _rooms = const [];
  List<RoomType> _roomTypes = const [];
  bool _loading = false;
  bool _working = false;
  String? _error;
  int _loadVersion = 0;

  List<Property> get _eligibleProperties => widget.agentStore.myListings
      .where(
        (property) =>
            property.businessModel == PropertyBusinessModel.bookable &&
            const {
              PropertyCategory.hotel,
              PropertyCategory.motel,
              PropertyCategory.lodge,
            }.contains(property.category),
      )
      .toList(growable: false);

  Property? get _property {
    for (final property in _eligibleProperties) {
      if (property.id == _propertyId) return property;
    }
    return null;
  }

  List<PhysicalRoom> get _filteredRooms => _rooms
      .where(
        (room) =>
            (_floor == null || room.floorLabel == _floor) &&
            (_categoryFilter == null || room.roomTypeId == _categoryFilter) &&
            room.roomNumber.toLowerCase().contains(_roomSearch.toLowerCase()),
      )
      .toList();

  List<PhysicalRoom> get _visibleRooms =>
      _filteredRooms.skip(_page * _pageSize).take(_pageSize).toList();

  @override
  void initState() {
    super.initState();
    final properties = _eligibleProperties;
    if (properties.isNotEmpty) {
      _propertyId = properties.first.id;
      _reload();
    }
  }

  @override
  void didUpdateWidget(covariant RoomInventoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_property == null && _eligibleProperties.isNotEmpty) {
      _propertyId = _eligibleProperties.first.id;
      _clearInventory();
      _reload();
    } else if (_property == null) {
      _loadVersion++;
      _clearInventory();
    }
  }

  void _clearInventory() {
    _rooms = const [];
    _roomTypes = const [];
    _selectedRoomIds.clear();
    _floor = null;
    _categoryFilter = null;
    _roomTypeId = null;
    _page = 0;
    _error = null;
    _loading = false;
  }

  Future<void> _reload() async {
    final propertyId = _propertyId;
    if (propertyId == null) return;
    final loadVersion = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait<Object>([
        widget.agentStore.loadPhysicalRooms(propertyId),
        widget.agentStore.loadRoomTypes(propertyId),
      ]);
      if (!mounted ||
          propertyId != _propertyId ||
          loadVersion != _loadVersion) {
        return;
      }
      setState(() {
        _rooms = values[0] as List<PhysicalRoom>;
        _roomTypes = values[1] as List<RoomType>;
        _selectedRoomIds.clear();
        _floor = null;
        _categoryFilter = null;
        _page = 0;
        _roomTypeId = _roomTypes.isEmpty ? null : _roomTypes.first.id;
      });
    } catch (error) {
      if (mounted && propertyId == _propertyId && loadVersion == _loadVersion) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && propertyId == _propertyId && loadVersion == _loadVersion) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _propertyPicker(Property property) => Row(
    children: [
      Expanded(
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: property.id,
          decoration: const InputDecoration(labelText: 'Property'),
          items: _eligibleProperties
              .map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(item.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: _working
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    _propertyId = value;
                    _clearInventory();
                  });
                  _reload();
                },
        ),
      ),
      const SizedBox(width: 12),
      IconButton(
        tooltip: 'Refresh inventory',
        onPressed: _loading ? null : _reload,
        icon: const Icon(HavenIcons.refresh),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final property = _property;
    if (property == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Add a hotel, motel, or lodge to manage room inventory.'),
        ),
      );
    }
    final assigned = _rooms.where((room) => room.roomTypeId != null).length;
    final floors =
        _rooms
            .map((room) => room.floorLabel)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    if (widget.view == RoomInventoryView.calendar) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _propertyPicker(property),
            const SizedBox(height: 12),
            Expanded(
              child: RoomCalendarPanel(
                key: ValueKey(property.id),
                store: widget.agentStore,
                propertyId: property.id,
              ),
            ),
          ],
        ),
      );
    }
    final showCategories = widget.view != RoomInventoryView.rooms;
    final showRooms = widget.view != RoomInventoryView.categories;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _propertyPicker(property),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (showCategories)
              _InventoryCount(label: 'Categories', value: _roomTypes.length),
            _InventoryCount(label: 'Total rooms', value: _rooms.length),
            _InventoryCount(label: 'Assigned', value: assigned),
            _InventoryCount(
              label: 'Unassigned',
              value: _rooms.length - assigned,
            ),
            _InventoryCount(
              label: 'Out of service',
              value: _rooms
                  .where((room) => room.status == 'outOfService')
                  .length,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (showRooms)
              FilledButton.icon(
                onPressed: _working || _loading || _rooms.isNotEmpty
                    ? null
                    : _showGenerateDialog,
                icon: const Icon(HavenIcons.autoAwesome),
                label: const Text('Generate rooms'),
              ),
            if (showCategories)
              OutlinedButton.icon(
                onPressed: _working || _loading ? null : _showCategoryDialog,
                icon: const Icon(HavenIcons.add),
                label: const Text('Add room category'),
              ),
            if (showRooms)
              OutlinedButton.icon(
                onPressed: _working || _loading ? null : _showAddRooms,
                icon: const Icon(HavenIcons.meetingRoomOutlined),
                label: const Text('Add rooms'),
              ),
            if (widget.view == RoomInventoryView.all)
              OutlinedButton.icon(
                onPressed: _working || _loading ? null : () => _showWalkIns(),
                icon: const Icon(HavenIcons.howToRegOutlined),
                label: const Text('Walk-in reservations'),
              ),
            if (widget.view == RoomInventoryView.all)
              OutlinedButton.icon(
                onPressed: _working || _loading
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) => RoomCalendarDialog(
                          store: widget.agentStore,
                          propertyId: property.id,
                        ),
                      ),
                icon: const Icon(HavenIcons.calendarMonthOutlined),
                label: const Text('Availability calendar'),
              ),
          ],
        ),
        if (showCategories && _roomTypes.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Room category distribution',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final type in _roomTypes)
            ListTile(
              dense: true,
              title: Text(type.name),
              subtitle: Text(
                '${_rooms.where((room) => room.roomTypeId == type.id).length} assigned / ${type.totalRooms} planned',
              ),
              trailing: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${formatTzs(type.nightlyPriceTzs)} / night'),
                  IconButton(
                    tooltip: 'Edit ${type.name}',
                    onPressed: _working
                        ? null
                        : () => _showCategoryDialog(type),
                    icon: const Icon(HavenIcons.editOutlined),
                  ),
                ],
              ),
            ),
        ],
        if (showCategories && showRooms) const Divider(height: 28),
        if (showRooms && _rooms.isNotEmpty) ...[
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search room identifier',
              prefixIcon: Icon(HavenIcons.search),
            ),
            onChanged: (value) => setState(() {
              _roomSearch = value.trim();
              _page = 0;
            }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: _categoryFilter,
            decoration: const InputDecoration(labelText: 'Filter by category'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All categories'),
              ),
              ..._roomTypes.map(
                (type) => DropdownMenuItem<String?>(
                  value: type.id,
                  child: Text(type.name),
                ),
              ),
            ],
            onChanged: (value) => setState(() {
              _categoryFilter = value;
              _page = 0;
            }),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _floor,
                  decoration: const InputDecoration(
                    labelText: 'Filter by floor',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All floors'),
                    ),
                    ...floors.map(
                      (floor) => DropdownMenuItem<String?>(
                        value: floor,
                        child: Text(floor),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _floor = value;
                    _page = 0;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => setState(() {
                  _selectedRoomIds = _visibleRooms
                      .map((room) => room.id)
                      .toSet();
                }),
                child: const Text('Select visible'),
              ),
              TextButton(
                onPressed: () => setState(() => _selectedRoomIds.clear()),
                child: const Text('Clear'),
              ),
            ],
          ),
          if (_roomTypes.isNotEmpty)
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _roomTypeId,
                    decoration: const InputDecoration(
                      labelText: 'Assign category',
                    ),
                    items: _roomTypes
                        .map(
                          (type) => DropdownMenuItem(
                            value: type.id,
                            child: Text(type.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _roomTypeId = value),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed:
                      _working ||
                          _selectedRoomIds.isEmpty ||
                          _roomTypeId == null
                      ? null
                      : _assignSelected,
                  child: Text('Assign ${_selectedRoomIds.length}'),
                ),
              ],
            ),
          const SizedBox(height: 8),
          if (_roomTypes.isEmpty)
            const Text('Add a room category before assigning rooms.'),
          for (final room in _visibleRooms)
            CheckboxListTile(
              value: _selectedRoomIds.contains(room.id),
              onChanged: (value) => setState(() {
                if (value == true) {
                  _selectedRoomIds.add(room.id);
                } else {
                  _selectedRoomIds.remove(room.id);
                }
              }),
              title: Text('Room ${room.roomNumber}'),
              subtitle: Text(
                [
                  if (room.floorLabel != null) room.floorLabel!,
                  room.roomTypeName ?? 'Unassigned',
                  if (room.nightlyPriceTzs != null)
                    '${formatTzs(room.nightlyPriceTzs!)} / night',
                  if (room.availabilityBlocks.isNotEmpty)
                    '${room.availabilityBlocks.length} maintenance block(s)',
                ].join(' · '),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              secondary: PopupMenuButton<String>(
                tooltip: 'Room actions',
                onSelected: (action) {
                  if (action == 'walk-in') {
                    _showWalkIns(room.id);
                  } else if (action == 'rename') {
                    _showRenameRoom(room);
                  } else {
                    _showBlockDialog(room);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'walk-in',
                    child: Text('Record walk-in'),
                  ),
                  const PopupMenuItem(
                    value: 'rename',
                    child: Text('Edit room identifier'),
                  ),
                  const PopupMenuItem(
                    value: 'maintenance',
                    child: Text('Manage maintenance dates'),
                  ),
                ],
              ),
            ),
          if (_filteredRooms.length > _pageSize)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(
                  onPressed: _page == 0 ? null : () => setState(() => _page--),
                  child: const Text('Previous'),
                ),
                Text(
                  'Page ${_page + 1} of ${(_filteredRooms.length / _pageSize).ceil()}',
                ),
                TextButton(
                  onPressed: (_page + 1) * _pageSize >= _filteredRooms.length
                      ? null
                      : () => setState(() => _page++),
                  child: const Text('Next'),
                ),
              ],
            ),
        ] else if (showRooms && !_loading) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No physical rooms have been generated. Generate inventory to start assigning categories.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
        if (_loading || _working)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Future<void> _showAddRooms() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add rooms without floors'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Room identifiers',
              helperText:
                  'Enter one identifier per line, such as A01 or VIP-B.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add rooms'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    final numbers = value
        .split(RegExp(r'[\r\n,]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (numbers.isEmpty) {
      setState(() => _error = 'Enter at least one room identifier.');
      return;
    }
    await _run(() async {
      await widget.agentStore.addPhysicalRooms(_propertyId!, numbers);
      await _reload();
    });
  }

  Future<void> _showRenameRoom(PhysicalRoom room) async {
    final controller = TextEditingController(text: room.roomNumber);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit room identifier'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Room identifier'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    if (value.isEmpty) {
      setState(() => _error = 'Enter a room identifier.');
      return;
    }
    await _run(() async {
      await widget.agentStore.renamePhysicalRoom(_propertyId!, room.id, value);
      await _reload();
    });
  }

  Future<void> _showWalkIns([String? roomId]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => WalkInDialog(
        store: widget.agentStore,
        propertyId: _propertyId!,
        rooms: _rooms,
        initialRoomId: roomId,
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _showGenerateDialog() async {
    final floors = await showDialog<List<RoomFloorConfiguration>>(
      context: context,
      builder: (context) => const _GenerateRoomsDialog(),
    );
    if (floors == null) return;
    await _run(() async {
      await widget.agentStore.generatePhysicalRooms(_propertyId!, floors);
      await _reload();
    });
  }

  Future<void> _showCategoryDialog([RoomType? initial]) async {
    final type = await showDialog<RoomType>(
      context: context,
      builder: (context) => RoomCategoryDialog(
        listingId: _propertyId!,
        defaultRooms: _rooms.isEmpty ? 1 : _rooms.length,
        initial: initial,
      ),
    );
    if (type == null) return;
    await _run(() async {
      await widget.agentStore.saveRoomType(type);
      await _reload();
    });
  }

  Future<void> _assignSelected() async {
    final ids = _selectedRoomIds.toList(growable: false);
    await _run(() async {
      await widget.agentStore.assignRooms(
        listingId: _propertyId!,
        roomIds: ids,
        roomTypeId: _roomTypeId!,
      );
      await _reload();
    });
  }

  Future<void> _showBlockDialog(PhysicalRoom room) async {
    final reason = TextEditingController();
    var startDate = DateUtils.dateOnly(
      DateTime.now().add(const Duration(days: 1)),
    );
    var endDate = startDate;
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Room ${room.roomNumber} maintenance dates'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (room.availabilityBlocks.isEmpty)
                    const Text('No maintenance dates are currently blocked.')
                  else ...[
                    const Text('Existing blocks'),
                    for (final block in room.availabilityBlocks)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${_dateLabel(block.startDate)} - ${_dateLabel(block.endDate.subtract(const Duration(days: 1)))}',
                        ),
                        subtitle: Text(block.reason),
                        trailing: IconButton(
                          tooltip: 'Remove maintenance block',
                          onPressed: saving
                              ? null
                              : () async {
                                  setDialogState(() => saving = true);
                                  try {
                                    await widget.agentStore.removeRoomBlock(
                                      listingId: _propertyId!,
                                      roomId: room.id,
                                      blockId: block.id,
                                    );
                                    await _reload();
                                    if (dialogContext.mounted) {
                                      Navigator.pop(dialogContext);
                                    }
                                  } catch (error) {
                                    if (mounted) {
                                      setState(() => _error = error.toString());
                                    }
                                  } finally {
                                    if (dialogContext.mounted) {
                                      setDialogState(() => saving = false);
                                    }
                                  }
                                },
                          icon: const Icon(HavenIcons.deleteOutline),
                        ),
                      ),
                  ],
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Unavailable from'),
                    subtitle: Text(_dateLabel(startDate)),
                    trailing: const Icon(HavenIcons.calendarTodayOutlined),
                    onTap: saving
                        ? null
                        : () async {
                            final selected = await showDatePicker(
                              context: context,
                              initialDate: startDate,
                              firstDate: DateUtils.dateOnly(DateTime.now()),
                              lastDate: DateTime(2100),
                            );
                            if (selected == null) return;
                            setDialogState(() {
                              startDate = DateUtils.dateOnly(selected);
                              if (endDate.isBefore(startDate)) {
                                endDate = startDate;
                              }
                            });
                          },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Unavailable through'),
                    subtitle: Text(_dateLabel(endDate)),
                    trailing: const Icon(HavenIcons.calendarTodayOutlined),
                    onTap: saving
                        ? null
                        : () async {
                            final selected = await showDatePicker(
                              context: context,
                              initialDate: endDate,
                              firstDate: startDate,
                              lastDate: DateTime(2100),
                            );
                            if (selected != null) {
                              setDialogState(
                                () => endDate = DateUtils.dateOnly(selected),
                              );
                            }
                          },
                  ),
                  TextField(
                    controller: reason,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      hintText: 'For example, scheduled maintenance',
                    ),
                    maxLength: 500,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: saving || reason.text.trim().length < 2
                  ? null
                  : () async {
                      setDialogState(() => saving = true);
                      try {
                        await widget.agentStore.blockRoomDates(
                          listingId: _propertyId!,
                          roomId: room.id,
                          startDate: startDate,
                          endDate: endDate.add(const Duration(days: 1)),
                          reason: reason.text.trim(),
                        );
                        await _reload();
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                      } catch (error) {
                        if (mounted) {
                          setState(() => _error = error.toString());
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          setDialogState(() => saving = false);
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Block dates'),
            ),
          ],
        ),
      ),
    );
    reason.dispose();
  }

  String _dateLabel(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}

class _InventoryCount extends StatelessWidget {
  const _InventoryCount({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text('$label: $value'),
    avatar: const Icon(HavenIcons.meetingRoomOutlined, size: 18),
  );
}

class _FloorDraft {
  _FloorDraft(int index)
    : label = TextEditingController(text: 'Floor $index'),
      roomCount = TextEditingController(text: '20'),
      startNumber = TextEditingController(
        text: '${index == 1 ? 1 : index * 100 + 1}',
      );

  final TextEditingController label;
  final TextEditingController roomCount;
  final TextEditingController startNumber;

  void dispose() {
    label.dispose();
    roomCount.dispose();
    startNumber.dispose();
  }
}

class _GenerateRoomsDialog extends StatefulWidget {
  const _GenerateRoomsDialog();

  @override
  State<_GenerateRoomsDialog> createState() => _GenerateRoomsDialogState();
}

class _GenerateRoomsDialogState extends State<_GenerateRoomsDialog> {
  final _floors = <_FloorDraft>[_FloorDraft(1)];

  @override
  void dispose() {
    for (final floor in _floors) {
      floor.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Generate physical rooms'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < _floors.length; index++)
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _floors[index].label,
                      decoration: const InputDecoration(
                        labelText: 'Floor label',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _floors[index].roomCount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Rooms'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _floors[index].startNumber,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Start number',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove floor',
                    onPressed: _floors.length == 1
                        ? null
                        : () => setState(() {
                            _floors.removeAt(index).dispose();
                          }),
                    icon: const Icon(HavenIcons.removeCircleOutline),
                  ),
                ],
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _floors.length >= 50
                    ? null
                    : () => setState(
                        () => _floors.add(_FloorDraft(_floors.length + 1)),
                      ),
                icon: const Icon(HavenIcons.add),
                label: const Text('Add floor'),
              ),
            ),
            const Text(
              'Room numbers must be unique within this property. A one-floor property can use any starting number.',
            ),
          ],
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
          final values = <RoomFloorConfiguration>[];
          for (final floor in _floors) {
            final count = int.tryParse(floor.roomCount.text);
            final start = int.tryParse(floor.startNumber.text);
            if (floor.label.text.trim().isEmpty ||
                count == null ||
                count < 1 ||
                count > 500 ||
                start == null) {
              return;
            }
            values.add(
              RoomFloorConfiguration(
                label: floor.label.text.trim(),
                roomCount: count,
                startNumber: start,
              ),
            );
          }
          Navigator.pop(context, values);
        },
        child: const Text('Generate'),
      ),
    ],
  );
}

/// Collects one room category; also used by the hotel registration wizard.
class RoomCategoryDialog extends StatefulWidget {
  const RoomCategoryDialog({
    super.key,
    required this.listingId,
    required this.defaultRooms,
    this.initial,
  });

  final String listingId;
  final int defaultRooms;
  final RoomType? initial;

  @override
  State<RoomCategoryDialog> createState() => _RoomCategoryDialogState();
}

class _RoomCategoryDialogState extends State<RoomCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _price = TextEditingController(
    text: widget.initial?.nightlyPriceTzs.toString(),
  );
  late final _capacity = TextEditingController(
    text: '${widget.initial?.capacity ?? 2}',
  );
  late final _quantity = TextEditingController(
    text: '${widget.initial?.totalRooms ?? widget.defaultRooms}',
  );
  late final _description = TextEditingController(
    text: widget.initial?.description,
  );
  late final _bedType = TextEditingController(text: widget.initial?.bedType);
  late final _numberOfBeds = TextEditingController(
    text: '${widget.initial?.numberOfBeds ?? 1}',
  );
  late final _bathroomType = TextEditingController(
    text: widget.initial?.bathroomType,
  );
  late final _sizeSqm = TextEditingController(
    text: widget.initial?.sizeSqm?.toString(),
  );
  late final _amenities = TextEditingController(
    text: widget.initial?.amenities.join(', '),
  );
  late final _amenityDetails = TextEditingController(
    text:
        widget.initial?.amenityDetails
            .map(
              (item) => item.description.trim().isEmpty
                  ? item.name
                  : '${item.name} | ${item.description}',
            )
            .join('\n') ??
        '',
  );
  static const _commonRoomAmenities = [
    'Wi-Fi',
    'Air conditioning',
    'Private bathroom',
    'Hot water',
    'Television',
    'Mini fridge',
    'Balcony',
    'Workspace',
    'Safe',
    'Room service',
    'Hair dryer',
    'Accessible room',
  ];
  late final Set<String> _selectedAmenities = {
    ...?widget.initial?.amenities,
    ...?widget.initial?.amenityDetails.map((item) => item.name),
  };
  late final _imageUrls = TextEditingController(
    text: widget.initial?.imageUrls.join('\n'),
  );

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _capacity.dispose();
    _quantity.dispose();
    _description.dispose();
    _bedType.dispose();
    _numberOfBeds.dispose();
    _bathroomType.dispose();
    _sizeSqm.dispose();
    _amenities.dispose();
    _amenityDetails.dispose();
    _imageUrls.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? 'Add room category' : 'Edit room category',
    ),
    content: Form(
      key: _formKey,
      child: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Category name'),
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Enter a category name.'
                    : null,
              ),
              TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Price per night (TZS)',
                ),
                validator: (value) =>
                    int.tryParse(value ?? '') == null || int.parse(value!) < 0
                    ? 'Enter a valid price.'
                    : null,
              ),
              TextFormField(
                controller: _capacity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Maximum guests'),
                validator: (value) =>
                    int.tryParse(value ?? '') == null ||
                        int.parse(value!) < 1 ||
                        int.parse(value) > 20
                    ? 'Enter a capacity from 1 to 20.'
                    : null,
              ),
              TextFormField(
                controller: _quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Planned category rooms',
                ),
                validator: (value) =>
                    int.tryParse(value ?? '') == null || int.parse(value!) < 1
                    ? 'Enter a positive quantity.'
                    : null,
              ),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(
                  labelText: 'Category description',
                ),
                maxLines: 3,
              ),
              TextFormField(
                controller: _bedType,
                decoration: const InputDecoration(labelText: 'Bed type'),
              ),
              TextFormField(
                controller: _numberOfBeds,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Number of beds'),
                validator: (value) =>
                    int.tryParse(value ?? '') == null || int.parse(value!) < 1
                    ? 'Enter a positive bed count.'
                    : null,
              ),
              TextFormField(
                controller: _bathroomType,
                decoration: const InputDecoration(labelText: 'Bathroom type'),
              ),
              TextFormField(
                controller: _sizeSqm,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Room size in m² (optional)',
                ),
                validator: (value) =>
                    value == null ||
                        value.trim().isEmpty ||
                        (double.tryParse(value) ?? -1) >= 0
                    ? null
                    : 'Enter a positive room size.',
              ),
              TextFormField(
                controller: _amenities,
                decoration: const InputDecoration(
                  labelText: 'Additional room amenities',
                  helperText: 'Legacy/simple room amenities, comma separated.',
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Common room facilities',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final amenity in _commonRoomAmenities)
                    FilterChip(
                      label: Text(amenity),
                      selected: _selectedAmenities.contains(amenity),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _selectedAmenities.add(amenity);
                        } else {
                          _selectedAmenities.remove(amenity);
                        }
                      }),
                    ),
                ],
              ),
              TextFormField(
                controller: _amenityDetails,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Room amenity descriptions',
                  helperText:
                      'One per line: Amenity name | optional guest guidance.',
                ),
                validator: _validateRoomAmenityDetails,
              ),
              TextFormField(
                controller: _imageUrls,
                decoration: const InputDecoration(
                  labelText: 'Room photo HTTPS URLs (one per line)',
                  helperText:
                      'The first URL is used as the primary category photo.',
                ),
                maxLines: 3,
                validator: (value) {
                  final urls = (value ?? '')
                      .split('\n')
                      .map((item) => item.trim())
                      .where((item) => item.isNotEmpty);
                  return urls.any(
                        (item) => Uri.tryParse(item)?.scheme != 'https',
                      )
                      ? 'Room photos must use secure HTTPS URLs.'
                      : null;
                },
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
          final imageUrls = _imageUrls.text
              .split('\n')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
          final amenityDetails = _parseRoomAmenityDetails(_amenityDetails.text);
          final amenityNames = <String>{
            ..._amenities.text
                .split(',')
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty),
            ..._selectedAmenities,
            ...amenityDetails.map((item) => item.name),
          };
          Navigator.pop(
            context,
            RoomType(
              id:
                  widget.initial?.id ??
                  'new-${DateTime.now().microsecondsSinceEpoch}',
              listingId: widget.listingId,
              name: _name.text.trim(),
              nightlyPriceTzs: int.parse(_price.text),
              capacity: int.parse(_capacity.text),
              totalRooms: int.parse(_quantity.text),
              description: _description.text.trim(),
              amenities: amenityNames.toList(growable: false),
              amenityDetails: amenityDetails,
              imageUrls: imageUrls,
              primaryImageUrl: imageUrls.isEmpty ? null : imageUrls.first,
              bedType: _bedType.text.trim(),
              numberOfBeds: int.parse(_numberOfBeds.text),
              bathroomType: _bathroomType.text.trim(),
              sizeSqm: _sizeSqm.text.trim().isEmpty
                  ? null
                  : double.parse(_sizeSqm.text),
            ),
          );
        },
        child: const Text('Save category'),
      ),
    ],
  );

  String? _validateRoomAmenityDetails(String? value) {
    final details = _parseRoomAmenityDetails(value ?? '');
    if (details.length > 100) return 'Enter no more than 100 amenities.';
    if (details.any((item) => item.name.length > 100)) {
      return 'Amenity names must be at most 100 characters.';
    }
    if (details.any((item) => item.description.length > 1000)) {
      return 'Amenity descriptions must be at most 1,000 characters.';
    }
    return null;
  }
}

List<AmenityDetail> _parseRoomAmenityDetails(String input) {
  final byName = <String, AmenityDetail>{};
  for (final line in input.split('\n')) {
    final parts = line.split('|');
    final name = parts.first.trim();
    if (name.isEmpty) continue;
    byName[name.toLowerCase()] = AmenityDetail(
      name: name,
      description: parts.length > 1 ? parts.skip(1).join('|').trim() : '',
    );
  }
  return byName.values.toList(growable: false);
}
