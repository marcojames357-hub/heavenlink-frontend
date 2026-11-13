import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/env_config.dart';
import '../../account/domain/account_models.dart';
import '../../payments/domain/unlock_record.dart';
import '../../properties/domain/property.dart';
import '../domain/agent_models.dart';
import '../domain/agent_repository.dart';

class HttpAgentRepository implements AgentRepository {
  HttpAgentRepository({required this.tokenProvider, http.Client? client})
    : _client = client ?? http.Client();

  final String? Function() tokenProvider;
  final http.Client _client;
  final Map<String, RoomType> _roomTypes = {};
  final Map<String, RoomInventory> _inventory = {};
  final Map<String, CheckInPolicy> _policies = {};
  final Map<String, AgentProfile> _profiles = {};

  @override
  Future<List<WalkInReservation>> loadWalkIns(String listingId) async {
    final result = await _request(
      'GET',
      '/api/v1/agents/walk-ins/${Uri.encodeComponent(listingId)}',
    );
    return (result['reservations'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(WalkInReservation.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> createWalkIn(
    String listingId,
    Map<String, Object?> values,
  ) async {
    await _request(
      'POST',
      '/api/v1/agents/walk-ins/${Uri.encodeComponent(listingId)}',
      body: values,
    );
  }

  @override
  Future<void> updateWalkIn(
    String listingId,
    String reservationId,
    String action,
    Map<String, Object?> values,
  ) async {
    await _request(
      'POST',
      '/api/v1/agents/walk-ins/${Uri.encodeComponent(listingId)}/${Uri.encodeComponent(reservationId)}/${Uri.encodeComponent(action)}',
      body: values,
    );
  }

  @override
  List<RoomType> roomTypes(String listingId) => _roomTypes.values
      .where((item) => item.listingId == listingId)
      .toList(growable: false);

  @override
  Future<List<RoomType>> loadRoomTypes(String listingId) async {
    final result = await _request(
      'GET',
      '/api/v1/agents/room-types/$listingId',
    );
    final values = (result['roomTypes'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_roomTypeFromJson)
        .toList(growable: false);
    _roomTypes.removeWhere((_, item) => item.listingId == listingId);
    for (final item in values) {
      _roomTypes[item.id] = item;
    }
    return values;
  }

  @override
  Future<RoomType> saveRoomType(RoomType roomType) async {
    final isExisting = !roomType.id.startsWith('new-');
    final path = isExisting
        ? '/api/v1/agents/room-types/${Uri.encodeComponent(roomType.id)}'
        : '/api/v1/agents/room-types';
    final result = await _request(
      isExisting ? 'PUT' : 'POST',
      path,
      body: {
        'listingId': roomType.listingId,
        'name': roomType.name,
        'description': roomType.description,
        'nightlyPriceTzs': roomType.nightlyPriceTzs,
        'capacity': roomType.capacity,
        'totalRooms': roomType.totalRooms,
        'amenities': roomType.amenities,
        'amenityDetails': roomType.amenityDetails
            .map((amenity) => amenity.toJson())
            .toList(growable: false),
        'imageUrls': roomType.imageUrls,
        'primaryImageUrl': roomType.primaryImageUrl,
        'bedType': roomType.bedType,
        'numberOfBeds': roomType.numberOfBeds,
        'bathroomType': roomType.bathroomType,
        'sizeSqm': roomType.sizeSqm,
      },
    );
    final json = result['roomType'];
    if (json is! Map<String, dynamic>) {
      throw StateError('The server did not return the saved room type.');
    }
    final saved = _roomTypeFromJson(json);
    _roomTypes[saved.id] = saved;
    return saved;
  }

  @override
  Future<void> deleteRoomType(String roomTypeId) async {
    await _request(
      'DELETE',
      '/api/v1/agents/room-types/${Uri.encodeComponent(roomTypeId)}',
    );
    _roomTypes.remove(roomTypeId);
  }

  @override
  CheckInPolicy policy(String listingId) =>
      _policies[listingId] ?? const CheckInPolicy();

  @override
  Future<CheckInPolicy> loadPolicy(String listingId) async {
    final result = await _request(
      'GET',
      '/api/v1/agents/checkin-policy/${Uri.encodeComponent(listingId)}',
    );
    final json = result['policy'];
    final policy = json is Map<String, dynamic>
        ? CheckInPolicy(
            checkInFrom: json['checkInFrom'] as String? ?? '14:00',
            checkOutBy: json['checkOutBy'] as String? ?? '11:00',
            cancellationHours:
                (json['cancellationHours'] as num?)?.toInt() ?? 24,
            allowLateCheckout: json['allowLateCheckout'] as bool? ?? false,
            notes: json['notes'] as String? ?? '',
          )
        : const CheckInPolicy();
    _policies[listingId] = policy;
    return policy;
  }

  @override
  Future<void> savePolicy(String listingId, CheckInPolicy policy) async {
    await _request(
      'PUT',
      '/api/v1/agents/checkin-policy/${Uri.encodeComponent(listingId)}',
      body: {
        'checkInFrom': policy.checkInFrom,
        'checkOutBy': policy.checkOutBy,
        'cancellationHours': policy.cancellationHours,
        'allowLateCheckout': policy.allowLateCheckout,
        'notes': policy.notes,
      },
    );
    _policies[listingId] = policy;
  }

  @override
  RoomInventory? inventory(String roomTypeId, DateTime date) =>
      _inventory[_inventoryKey(roomTypeId, date)];

  @override
  Future<List<RoomInventory>> loadInventory(String roomTypeId) async {
    final result = await _request(
      'GET',
      '/api/v1/agents/inventory/${Uri.encodeComponent(roomTypeId)}',
    );
    final values = (result['inventory'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_inventoryFromJson)
        .toList(growable: false);
    _inventory.removeWhere((_, item) => item.roomTypeId == roomTypeId);
    for (final item in values) {
      _inventory[_inventoryKey(item.roomTypeId, item.date)] = item;
    }
    return values;
  }

  @override
  Future<void> saveInventory(RoomInventory entry) async {
    final body = <String, Object?>{
      'roomTypeId': entry.roomTypeId,
      'date': _dateOnly(entry.date),
      'booked': entry.booked,
    };
    if (entry.totalOverride != null) {
      body['totalOverride'] = entry.totalOverride;
    }
    await _request('POST', '/api/v1/agents/inventory', body: body);
    _inventory[_inventoryKey(entry.roomTypeId, entry.date)] = entry;
  }

  @override
  List<PhysicalRoom> physicalRooms(String listingId) => const [];

  @override
  Future<List<PhysicalRoom>> loadPhysicalRooms(String listingId) async {
    final result = await _request(
      'GET',
      '/api/v1/agents/rooms/${Uri.encodeComponent(listingId)}',
    );
    return (result['rooms'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((json) {
          final floor = json['floor'] as Map<String, dynamic>?;
          final roomType = json['roomType'] as Map<String, dynamic>?;
          return PhysicalRoom(
            id: json['id'] as String? ?? '',
            propertyId: json['propertyId'] as String? ?? listingId,
            roomNumber: json['roomNumber'] as String? ?? '',
            status: json['status'] as String? ?? 'active',
            floorLabel: floor?['label'] as String?,
            roomTypeId: json['roomTypeId'] as String?,
            roomTypeName: roomType?['name'] as String?,
            nightlyPriceTzs: (roomType?['nightlyPriceTzs'] as num?)?.toInt(),
            availabilityBlocks:
                (json['availabilityBlocks'] as List<dynamic>? ?? const [])
                    .whereType<Map<String, dynamic>>()
                    .map(
                      (block) => RoomAvailabilityBlock(
                        id: block['id'] as String? ?? '',
                        startDate: DateTime.parse(block['startDate'] as String),
                        endDate: DateTime.parse(block['endDate'] as String),
                        reason: block['reason'] as String? ?? '',
                      ),
                    )
                    .toList(growable: false),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<List<RoomCalendarEntry>> loadRoomCalendar(
    String listingId,
    DateTime start,
    DateTime end,
  ) async {
    final result = await _request(
      'GET',
      '/api/v1/agents/rooms/${Uri.encodeComponent(listingId)}/calendar?start=${_dateOnly(start)}&end=${_dateOnly(end)}',
    );
    return (result['rooms'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(RoomCalendarEntry.fromJson)
        .toList();
  }

  @override
  Future<void> addPhysicalRooms(
    String listingId,
    List<String> roomNumbers,
  ) async {
    await _request(
      'POST',
      '/api/v1/agents/rooms/${Uri.encodeComponent(listingId)}/manual',
      body: {'roomNumbers': roomNumbers},
    );
  }

  @override
  Future<void> renamePhysicalRoom(
    String listingId,
    String roomId,
    String roomNumber,
  ) async {
    await _request(
      'PATCH',
      '/api/v1/agents/rooms/${Uri.encodeComponent(listingId)}/${Uri.encodeComponent(roomId)}',
      body: {'roomNumber': roomNumber},
    );
  }

  @override
  Future<void> generatePhysicalRooms(
    String listingId,
    List<RoomFloorConfiguration> floors,
  ) async {
    await _request(
      'POST',
      '/api/v1/agents/rooms/${Uri.encodeComponent(listingId)}/generate',
      body: {
        'floors': floors
            .map(
              (floor) => {
                'label': floor.label,
                'roomCount': floor.roomCount,
                if (floor.startNumber != null) 'startNumber': floor.startNumber,
              },
            )
            .toList(growable: false),
      },
    );
  }

  @override
  Future<void> assignRooms({
    required String listingId,
    required List<String> roomIds,
    required String roomTypeId,
  }) async {
    await _request(
      'POST',
      '/api/v1/agents/rooms/assign',
      body: {
        'listingId': listingId,
        'roomIds': roomIds,
        'roomTypeId': roomTypeId,
      },
    );
  }

  @override
  Future<void> blockRoomDates({
    required String listingId,
    required String roomId,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
  }) async {
    await _request(
      'POST',
      '/api/v1/agents/rooms/${Uri.encodeComponent(listingId)}/${Uri.encodeComponent(roomId)}/blocks',
      body: {
        'startDate': _dateOnly(startDate),
        'endDate': _dateOnly(endDate),
        'reason': reason,
      },
    );
  }

  @override
  Future<void> removeRoomBlock({
    required String listingId,
    required String roomId,
    required String blockId,
  }) async {
    await _request(
      'DELETE',
      '/api/v1/agents/rooms/${Uri.encodeComponent(listingId)}/${Uri.encodeComponent(roomId)}/blocks/${Uri.encodeComponent(blockId)}',
    );
  }

  @override
  List<GuestMessage> messages(String bookingId) => const [];

  @override
  Future<List<GuestMessage>> loadMessages(String bookingId) async {
    final result = await _request(
      'GET',
      '/api/v1/agents/messages/${Uri.encodeComponent(bookingId)}',
    );
    return (result['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (json) => GuestMessage(
            id: json['id'] as String? ?? '',
            bookingId: json['bookingId'] as String? ?? bookingId,
            sender: json['senderType'] as String? ?? 'guest',
            body: json['body'] as String? ?? '',
            sentAt:
                DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> sendMessage(GuestMessage message) async {
    await _request(
      'POST',
      '/api/v1/agents/messages',
      body: {'bookingId': message.bookingId, 'body': message.body},
    );
  }

  @override
  AgentProfile? profile(String userId) => _profiles[userId];

  @override
  Future<AgentProfile> loadProfile(String userId, AccountRole role) async {
    final result = await _request('GET', '/api/v1/agents/profile');
    final json = result['profile'];
    if (json is! Map<String, dynamic>) {
      throw StateError('The server did not return the agent profile.');
    }
    final profile = AgentProfile(
      userId: json['userId'] as String? ?? userId,
      displayName: json['displayName'] as String? ?? '',
      agencyName: json['agencyName'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      photoUrl: json['photoUrl'] as String? ?? '',
      videoUrl: json['videoUrl'] as String? ?? '',
      role: role,
      capabilities: (json['capabilities'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map(
            (value) => AgentCapability.values.firstWhere(
              (capability) => capability.name == value,
              orElse: () => AgentCapability.rentalProperty,
            ),
          )
          .toSet(),
      serviceAreas: (json['serviceAreas'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
    );
    _profiles[userId] = profile;
    return profile;
  }

  @override
  Future<void> saveProfile(AgentProfile profile) async {
    final result = await _request(
      'PUT',
      '/api/v1/agents/profile',
      body: {
        'displayName': profile.displayName,
        'agencyName': profile.agencyName,
        'bio': profile.bio,
        'photoUrl': profile.photoUrl,
        'videoUrl': profile.videoUrl,
        'serviceAreas': profile.serviceAreas,
      },
    );
    final json = result['profile'];
    if (json is! Map<String, dynamic>) {
      throw StateError('The server did not return the saved agent profile.');
    }
    _profiles[profile.userId] = AgentProfile(
      userId: profile.userId,
      displayName: json['displayName'] as String? ?? profile.displayName,
      agencyName: json['agencyName'] as String? ?? profile.agencyName,
      bio: json['bio'] as String? ?? profile.bio,
      photoUrl: json['photoUrl'] as String? ?? profile.photoUrl,
      videoUrl: json['videoUrl'] as String? ?? profile.videoUrl,
      serviceAreas: (json['serviceAreas'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      role: profile.role,
      capabilities: profile.capabilities,
      phone: profile.phone,
      email: profile.email,
    );
  }

  @override
  Future<List<Booking>> loadBookings() async {
    final result = await _request('GET', '/api/v1/agents/bookings');
    return (result['bookings'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_bookingFromJson)
        .toList(growable: false);
  }

  @override
  Future<void> updateBookingStatus(String bookingId, String status) async {
    await _request(
      'PATCH',
      '/api/v1/bookings/${Uri.encodeComponent(bookingId)}/status',
      body: {'status': status},
    );
  }

  @override
  Future<List<UnlockActivity>> loadUnlockActivity() async {
    final result = await _request('GET', '/api/v1/agents/unlock-activity');
    return (result['unlocks'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((json) {
          final property = json['property'];
          final status = UnlockStatus.values.firstWhere(
            (value) => value.name == json['status'],
            orElse: () => UnlockStatus.failed,
          );
          return UnlockActivity(
            listingName: property is Map<String, dynamic>
                ? property['name'] as String? ?? ''
                : '',
            record: UnlockRecord(
              id: json['id'] as String? ?? '',
              customerId: json['customerId'] as String? ?? '',
              listingId: json['listingId'] as String? ?? '',
              paymentTransactionId:
                  json['paymentTransactionId'] as String? ?? '',
              status: status,
              createdAt:
                  DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                  DateTime.now(),
              confirmedAt: DateTime.tryParse(
                json['confirmedAt'] as String? ?? '',
              ),
              amountTzs: (json['amountTzs'] as num?)?.toInt(),
            ),
          );
        })
        .toList(growable: false);
  }

  RoomType _roomTypeFromJson(Map<String, dynamic> json) => RoomType(
    id: json['id'] as String? ?? '',
    listingId: json['listingId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    nightlyPriceTzs: (json['nightlyPriceTzs'] as num?)?.toInt() ?? 0,
    capacity: (json['capacity'] as num?)?.toInt() ?? 1,
    totalRooms: (json['totalRooms'] as num?)?.toInt() ?? 1,
    amenities: (json['amenities'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false),
    amenityDetails: (json['amenityDetails'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AmenityDetail.fromJson)
        .toList(growable: false),
    imageUrls: (json['imageUrls'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false),
    primaryImageUrl: json['primaryImageUrl'] as String?,
    bedType: json['bedType'] as String?,
    numberOfBeds: (json['numberOfBeds'] as num?)?.toInt(),
    bathroomType: json['bathroomType'] as String?,
    sizeSqm: (json['sizeSqm'] as num?)?.toDouble(),
  );

  RoomInventory _inventoryFromJson(Map<String, dynamic> json) => RoomInventory(
    roomTypeId: json['roomTypeId'] as String? ?? '',
    date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
    booked: (json['booked'] as num?)?.toInt() ?? 0,
    totalOverride: (json['totalOverride'] as num?)?.toInt(),
  );

  Booking _bookingFromJson(Map<String, dynamic> json) {
    final propertyData = json['property'];
    if (propertyData is! Map<String, dynamic>) {
      throw StateError('The server returned a booking without its property.');
    }
    final property = Property(
      id: propertyData['id'] as String? ?? json['propertyId'] as String? ?? '',
      name: propertyData['name'] as String? ?? '',
      city: propertyData['city'] as String? ?? '',
      neighborhood: propertyData['neighborhood'] as String? ?? '',
      priceTzs: (propertyData['priceTzs'] as num?)?.toInt() ?? 0,
      businessModel: PropertyBusinessModel.bookable,
      category: PropertyCategory.values.firstWhere(
        (value) =>
            value.name ==
            (propertyData['accommodationType'] ?? propertyData['category']),
        orElse: () => PropertyCategory.hotel,
      ),
      imageUrl: propertyData['imageUrl'] as String? ?? '',
      imageUrls: (propertyData['imageUrls'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      rating: (propertyData['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (propertyData['reviewCount'] as num?)?.toInt() ?? 0,
      bedrooms: (propertyData['bedrooms'] as num?)?.toInt() ?? 0,
      bathrooms: (propertyData['bathrooms'] as num?)?.toInt() ?? 0,
      amenities: (propertyData['amenities'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      description: propertyData['description'] as String? ?? '',
      available: propertyData['available'] as bool? ?? true,
      furnished: propertyData['furnished'] as bool? ?? false,
      parking: propertyData['parking'] as bool? ?? false,
      water: propertyData['water'] as bool? ?? false,
      electricity: propertyData['electricity'] as bool? ?? false,
      security: propertyData['security'] as bool? ?? false,
      propertyVerification: VerificationStatus.unverified,
      ownerVerification: VerificationStatus.unverified,
      managerName: propertyData['managerName'] as String? ?? '',
      listingStatus: ListingStatus.published,
      agentId: propertyData['agentId'] as String? ?? '',
    );
    final status = switch (json['status']) {
      'confirmed' => BookingStatus.active,
      'completed' => BookingStatus.completed,
      'cancelled' => BookingStatus.cancelled,
      _ => BookingStatus.pending,
    };
    return Booking(
      id: json['id'] as String? ?? '',
      property: property,
      checkIn: DateTime.parse(json['checkIn'] as String),
      checkOut: DateTime.parse(json['checkOut'] as String),
      guestName: json['guestName'] as String? ?? '',
      subtotalTzs: (json['subtotalTzs'] as num?)?.toInt() ?? 0,
      feeTzs: (json['feeTzs'] as num?)?.toInt() ?? 0,
      totalTzs: (json['totalTzs'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      status: status,
      roomTypeName:
          (json['roomType'] as Map<String, dynamic>?)?['name'] as String?,
      assignedRoomNumber:
          (json['assignedRoom'] as Map<String, dynamic>?)?['roomNumber']
              as String?,
      paymentTransactionId: json['paymentTransactionId'] as String?,
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final token = tokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in to manage agent listings.');
    }
    try {
      final request = http.Request(method, EnvConfig.endpoint(path))
        ..headers.addAll({
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        });
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed);
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      if (response.statusCode >= 400) {
        final message = decoded is Map<String, dynamic>
            ? decoded['message'] as String? ?? decoded['error'] as String?
            : null;
        throw StateError(message ?? 'The agent request was rejected.');
      }
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError(
        'We could not reach Haven Link agent services. Check your connection.',
      );
    }
  }

  String _inventoryKey(String roomTypeId, DateTime date) =>
      '$roomTypeId|${_dateOnly(date)}';

  String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
