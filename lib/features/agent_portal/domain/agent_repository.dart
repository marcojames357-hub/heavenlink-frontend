import '../../account/domain/account_models.dart';
import '../../properties/domain/property.dart';
import 'agent_models.dart';

/// Data access for agent-owned working data: room types, inventory, policies
/// and guest messages.
///
/// Listings themselves are read through `PropertyRepository` so there is one
/// source of truth for moderation state.
abstract interface class AgentRepository {
  List<RoomType> roomTypes(String listingId);
  Future<List<RoomType>> loadRoomTypes(String listingId);
  Future<RoomType> saveRoomType(RoomType roomType);
  Future<void> deleteRoomType(String roomTypeId);

  CheckInPolicy policy(String listingId);
  Future<CheckInPolicy> loadPolicy(String listingId);
  Future<void> savePolicy(String listingId, CheckInPolicy policy);

  RoomInventory? inventory(String roomTypeId, DateTime date);
  Future<List<RoomInventory>> loadInventory(String roomTypeId);
  Future<void> saveInventory(RoomInventory entry);
  List<PhysicalRoom> physicalRooms(String listingId);
  Future<List<PhysicalRoom>> loadPhysicalRooms(String listingId);
  Future<List<RoomCalendarEntry>> loadRoomCalendar(
    String listingId,
    DateTime start,
    DateTime end,
  );
  Future<void> addPhysicalRooms(String listingId, List<String> roomNumbers);
  Future<void> renamePhysicalRoom(
    String listingId,
    String roomId,
    String roomNumber,
  );
  Future<void> generatePhysicalRooms(
    String listingId,
    List<RoomFloorConfiguration> floors,
  );
  Future<void> assignRooms({
    required String listingId,
    required List<String> roomIds,
    required String roomTypeId,
  });
  Future<void> blockRoomDates({
    required String listingId,
    required String roomId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  });
  Future<void> removeRoomBlock({
    required String listingId,
    required String roomId,
    required String blockId,
  });
  Future<List<WalkInReservation>> loadWalkIns(String listingId);
  Future<void> createWalkIn(String listingId, Map<String, Object?> values);
  Future<void> updateWalkIn(
    String listingId,
    String reservationId,
    String action,
    Map<String, Object?> values,
  );

  List<GuestMessage> messages(String bookingId);
  Future<List<GuestMessage>> loadMessages(String bookingId);
  Future<void> sendMessage(GuestMessage message);

  AgentProfile? profile(String userId);
  Future<AgentProfile> loadProfile(String userId, AccountRole role);
  Future<void> saveProfile(AgentProfile profile);

  Future<List<Booking>> loadBookings();
  Future<void> updateBookingStatus(String bookingId, String status);
  Future<List<UnlockActivity>> loadUnlockActivity();
}

/// In-memory implementation used until the backend is connected.
class LocalAgentRepository implements AgentRepository {
  LocalAgentRepository({AgentProfile? seedProfile})
    : _profiles = seedProfile == null
          ? const <String, AgentProfile>{}
          : <String, AgentProfile>{seedProfile.userId: seedProfile};

  final Map<String, RoomType> _roomTypes = {};
  final Map<String, CheckInPolicy> _policies = {};
  final Map<String, RoomInventory> _inventory = {};
  final Map<String, PhysicalRoom> _physicalRooms = {};
  final Map<String, RoomAvailabilityBlock> _availabilityBlocks = {};
  final Map<String, List<GuestMessage>> _messages = {};
  final Map<String, AgentProfile> _profiles;

  @override
  Future<List<WalkInReservation>> loadWalkIns(String listingId) async =>
      throw StateError('Walk-in reservations require a connected backend.');

  @override
  Future<void> createWalkIn(
    String listingId,
    Map<String, Object?> values,
  ) async =>
      throw StateError('Walk-in reservations require a connected backend.');

  @override
  Future<void> updateWalkIn(
    String listingId,
    String reservationId,
    String action,
    Map<String, Object?> values,
  ) async =>
      throw StateError('Walk-in reservations require a connected backend.');

  @override
  List<RoomType> roomTypes(String listingId) =>
      _roomTypes.values.where((item) => item.listingId == listingId).toList();

  @override
  Future<List<RoomType>> loadRoomTypes(String listingId) async =>
      roomTypes(listingId);

  @override
  Future<RoomType> saveRoomType(RoomType roomType) async {
    _roomTypes[roomType.id] = roomType;
    return roomType;
  }

  @override
  Future<void> deleteRoomType(String roomTypeId) async {
    _roomTypes.remove(roomTypeId);
  }

  @override
  CheckInPolicy policy(String listingId) =>
      _policies[listingId] ?? const CheckInPolicy();

  @override
  Future<CheckInPolicy> loadPolicy(String listingId) async => policy(listingId);

  @override
  Future<void> savePolicy(String listingId, CheckInPolicy value) async {
    _policies[listingId] = value;
  }

  @override
  RoomInventory? inventory(String roomTypeId, DateTime date) =>
      _inventory['$roomTypeId|${date.toIso8601String()}'];

  @override
  Future<List<RoomInventory>> loadInventory(String roomTypeId) async =>
      _inventory.values
          .where((item) => item.roomTypeId == roomTypeId)
          .toList(growable: false);

  @override
  Future<void> saveInventory(RoomInventory entry) async {
    _inventory['${entry.roomTypeId}|${entry.date.toIso8601String()}'] = entry;
  }

  @override
  List<PhysicalRoom> physicalRooms(String listingId) => _physicalRooms.values
      .where((room) => room.propertyId == listingId)
      .map(
        (room) => room.copyWith(
          availabilityBlocks: _availabilityBlocks.values
              .where((block) => block.id.startsWith('${room.id}|'))
              .toList(growable: false),
        ),
      )
      .toList(growable: false);

  @override
  Future<List<PhysicalRoom>> loadPhysicalRooms(String listingId) async =>
      physicalRooms(listingId);

  @override
  Future<List<RoomCalendarEntry>> loadRoomCalendar(
    String listingId,
    DateTime start,
    DateTime end,
  ) async => throw StateError(
    'The shared room calendar requires a connected backend.',
  );

  @override
  Future<void> addPhysicalRooms(
    String listingId,
    List<String> roomNumbers,
  ) async {
    final existing = physicalRooms(
      listingId,
    ).map((room) => room.roomNumber.toLowerCase()).toSet();
    for (final name in roomNumbers) {
      if (name.trim().isEmpty || !existing.add(name.toLowerCase())) {
        throw StateError('Room identifiers must be unique and non-empty.');
      }
    }
    for (final name in roomNumbers) {
      final id =
          '$listingId:manual:${DateTime.now().microsecondsSinceEpoch}:${name.hashCode}';
      _physicalRooms[id] = PhysicalRoom(
        id: id,
        propertyId: listingId,
        roomNumber: name,
        status: 'active',
      );
    }
  }

  @override
  Future<void> renamePhysicalRoom(
    String listingId,
    String roomId,
    String roomNumber,
  ) async {
    final room = _physicalRooms[roomId];
    if (room == null || room.propertyId != listingId) {
      throw StateError('Room not found.');
    }
    if (roomNumber.trim().isEmpty ||
        physicalRooms(listingId).any(
          (item) =>
              item.id != roomId &&
              item.roomNumber.toLowerCase() == roomNumber.toLowerCase(),
        )) {
      throw StateError('Room identifiers must be unique and non-empty.');
    }
    _physicalRooms[roomId] = room.copyWith(roomNumber: roomNumber);
  }

  @override
  Future<void> generatePhysicalRooms(
    String listingId,
    List<RoomFloorConfiguration> floors,
  ) async {
    if (physicalRooms(listingId).isNotEmpty) {
      throw StateError('Rooms already exist for this property.');
    }
    for (var index = 0; index < floors.length; index++) {
      final floor = floors[index];
      final start =
          floor.startNumber ?? (floors.length == 1 ? 1 : (index + 1) * 100 + 1);
      for (var offset = 0; offset < floor.roomCount; offset++) {
        final id = '$listingId:${floor.label}:${start + offset}';
        _physicalRooms[id] = PhysicalRoom(
          id: id,
          propertyId: listingId,
          roomNumber: '${start + offset}',
          floorLabel: floor.label,
          status: 'active',
        );
      }
    }
  }

  @override
  Future<void> assignRooms({
    required String listingId,
    required List<String> roomIds,
    required String roomTypeId,
  }) async {
    final type = _roomTypes[roomTypeId];
    if (type == null || type.listingId != listingId) {
      throw StateError('Choose a room category for this property.');
    }
    for (final id in roomIds) {
      final room = _physicalRooms[id];
      if (room == null || room.propertyId != listingId) {
        throw StateError('The selected rooms are no longer available.');
      }
      _physicalRooms[id] = room.copyWith(
        roomTypeId: type.id,
        roomTypeName: type.name,
        nightlyPriceTzs: type.nightlyPriceTzs,
      );
    }
  }

  @override
  Future<void> blockRoomDates({
    required String listingId,
    required String roomId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    final room = _physicalRooms[roomId];
    if (room == null || room.propertyId != listingId) {
      throw StateError('The selected room is no longer available.');
    }
    if (!endDate.isAfter(startDate) || reason.trim().length < 2) {
      throw StateError('Provide a valid date range and maintenance reason.');
    }
    final id = '$roomId|${DateTime.now().microsecondsSinceEpoch}';
    _availabilityBlocks[id] = RoomAvailabilityBlock(
      id: id,
      startDate: startDate,
      endDate: endDate,
      reason: reason.trim(),
    );
  }

  @override
  Future<void> removeRoomBlock({
    required String listingId,
    required String roomId,
    required String blockId,
  }) async {
    final block = _availabilityBlocks[blockId];
    if (block == null || !blockId.startsWith('$roomId|')) {
      throw StateError('The maintenance block is no longer available.');
    }
    if (_physicalRooms[roomId]?.propertyId != listingId) {
      throw StateError('The selected room is no longer available.');
    }
    _availabilityBlocks.remove(blockId);
  }

  @override
  List<GuestMessage> messages(String bookingId) =>
      List.of(_messages[bookingId] ?? const []);

  @override
  Future<List<GuestMessage>> loadMessages(String bookingId) async =>
      messages(bookingId);

  @override
  Future<void> sendMessage(GuestMessage message) async {
    _messages.putIfAbsent(message.bookingId, () => []).add(message);
  }

  @override
  AgentProfile? profile(String userId) => _profiles[userId];

  @override
  Future<AgentProfile> loadProfile(String userId, AccountRole role) async =>
      _profiles[userId] ??
      AgentProfile(userId: userId, displayName: '', role: role);

  @override
  Future<void> saveProfile(AgentProfile profile) async {
    _profiles[profile.userId] = profile;
  }

  @override
  Future<List<Booking>> loadBookings() async => const [];

  @override
  Future<void> updateBookingStatus(String bookingId, String status) async {
    throw StateError('Agent booking updates require a configured backend.');
  }

  @override
  Future<List<UnlockActivity>> loadUnlockActivity() async => const [];
}
