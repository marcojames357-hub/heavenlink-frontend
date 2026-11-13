import '../../payments/domain/unlock_record.dart';
import '../../properties/domain/property.dart';

/// A customer's completed contact unlock on an agent's listing.
class UnlockActivity {
  const UnlockActivity({required this.record, required this.listingName});

  final UnlockRecord record;
  final String listingName;
}

/// A bookable room category inside an accommodation listing.
class RoomType {
  const RoomType({
    required this.id,
    required this.listingId,
    required this.name,
    required this.nightlyPriceTzs,
    required this.capacity,
    required this.totalRooms,
    this.amenities = const [],
    this.amenityDetails = const [],
    this.description = '',
    this.imageUrls = const [],
    this.primaryImageUrl,
    this.bedType,
    this.numberOfBeds,
    this.bathroomType,
    this.sizeSqm,
  });

  final String id;
  final String listingId;
  final String name;
  final int nightlyPriceTzs;
  final int capacity;
  final int totalRooms;
  final List<String> amenities;
  final List<AmenityDetail> amenityDetails;
  final String description;
  final List<String> imageUrls;
  final String? primaryImageUrl;
  final String? bedType;
  final int? numberOfBeds;
  final String? bathroomType;
  final double? sizeSqm;

  RoomType copyWith({
    String? name,
    int? nightlyPriceTzs,
    int? capacity,
    int? totalRooms,
    List<String>? amenities,
    List<AmenityDetail>? amenityDetails,
    String? description,
    List<String>? imageUrls,
    String? primaryImageUrl,
    String? bedType,
    int? numberOfBeds,
    String? bathroomType,
    double? sizeSqm,
  }) {
    return RoomType(
      id: id,
      listingId: listingId,
      name: name ?? this.name,
      nightlyPriceTzs: nightlyPriceTzs ?? this.nightlyPriceTzs,
      capacity: capacity ?? this.capacity,
      totalRooms: totalRooms ?? this.totalRooms,
      amenities: amenities ?? this.amenities,
      amenityDetails: amenityDetails ?? this.amenityDetails,
      description: description ?? this.description,
      imageUrls: imageUrls ?? this.imageUrls,
      primaryImageUrl: primaryImageUrl ?? this.primaryImageUrl,
      bedType: bedType ?? this.bedType,
      numberOfBeds: numberOfBeds ?? this.numberOfBeds,
      bathroomType: bathroomType ?? this.bathroomType,
      sizeSqm: sizeSqm ?? this.sizeSqm,
    );
  }
}

class RoomFloorConfiguration {
  const RoomFloorConfiguration({
    required this.label,
    required this.roomCount,
    this.startNumber,
  });

  final String label;
  final int roomCount;
  final int? startNumber;
}

class PhysicalRoom {
  const PhysicalRoom({
    required this.id,
    required this.propertyId,
    required this.roomNumber,
    required this.status,
    this.floorLabel,
    this.roomTypeId,
    this.roomTypeName,
    this.nightlyPriceTzs,
    this.availabilityBlocks = const [],
  });

  final String id;
  final String propertyId;
  final String roomNumber;
  final String status;
  final String? floorLabel;
  final String? roomTypeId;
  final String? roomTypeName;
  final int? nightlyPriceTzs;
  final List<RoomAvailabilityBlock> availabilityBlocks;

  PhysicalRoom copyWith({
    String? roomNumber,
    String? roomTypeId,
    String? roomTypeName,
    int? nightlyPriceTzs,
    List<RoomAvailabilityBlock>? availabilityBlocks,
  }) => PhysicalRoom(
    id: id,
    propertyId: propertyId,
    roomNumber: roomNumber ?? this.roomNumber,
    status: status,
    floorLabel: floorLabel,
    roomTypeId: roomTypeId ?? this.roomTypeId,
    roomTypeName: roomTypeName ?? this.roomTypeName,
    nightlyPriceTzs: nightlyPriceTzs ?? this.nightlyPriceTzs,
    availabilityBlocks: availabilityBlocks ?? this.availabilityBlocks,
  );
}

class RoomAvailabilityBlock {
  const RoomAvailabilityBlock({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.reason,
  });

  final String id;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
}

class RoomCalendarEvent {
  const RoomCalendarEvent({
    required this.kind,
    required this.start,
    required this.end,
    this.guestName,
    this.reason,
    this.overdue = false,
  });
  final String kind;
  final DateTime start;
  final DateTime end;
  final String? guestName;
  final String? reason;
  final bool overdue;

  factory RoomCalendarEvent.fromJson(Map<String, dynamic> json) =>
      RoomCalendarEvent(
        kind: json['kind'] as String,
        start: _parseCalendarDate(json['start'] as String),
        end: _parseCalendarDate(json['end'] as String),
        guestName: json['guestName'] as String?,
        reason: json['reason'] as String?,
        overdue: json['overdue'] as bool? ?? false,
      );
}

DateTime _parseCalendarDate(String value) =>
    DateTime.parse(value.length == 10 ? '${value}T00:00:00Z' : value);

class RoomCalendarEntry {
  const RoomCalendarEntry({
    required this.roomNumber,
    required this.status,
    required this.occupancy,
    required this.events,
    this.floor,
    this.category,
  });
  final String roomNumber;
  final String status;
  final String occupancy;
  final String? floor;
  final String? category;
  final List<RoomCalendarEvent> events;

  factory RoomCalendarEntry.fromJson(Map<String, dynamic> json) =>
      RoomCalendarEntry(
        roomNumber: json['roomNumber'] as String,
        status: json['status'] as String,
        occupancy: json['occupancy'] as String,
        floor: json['floor'] as String?,
        category: json['category'] as String?,
        events: (json['events'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(RoomCalendarEvent.fromJson)
            .toList(),
      );
}

/// How many rooms of a type are already reserved on a given day.
class RoomInventory {
  const RoomInventory({
    required this.roomTypeId,
    required this.date,
    required this.booked,
    this.totalOverride,
  });

  final String roomTypeId;
  final DateTime date;
  final int booked;

  /// Overrides the room type's default capacity for this date, or `null` to
  /// close out the day entirely.
  final int? totalOverride;

  int totalFor(RoomType type) => totalOverride ?? type.totalRooms;

  int availableFor(RoomType type) =>
      (totalFor(type) - booked).clamp(0, 1 << 30);
}

/// Check-in / check-out rules shown to guests before they pay.
class CheckInPolicy {
  const CheckInPolicy({
    this.checkInFrom = '14:00',
    this.checkOutBy = '11:00',
    this.cancellationHours = 24,
    this.allowLateCheckout = false,
    this.notes = '',
  });

  final String checkInFrom;
  final String checkOutBy;
  final int cancellationHours;
  final bool allowLateCheckout;
  final String notes;

  CheckInPolicy copyWith({
    String? checkInFrom,
    String? checkOutBy,
    int? cancellationHours,
    bool? allowLateCheckout,
    String? notes,
  }) {
    return CheckInPolicy(
      checkInFrom: checkInFrom ?? this.checkInFrom,
      checkOutBy: checkOutBy ?? this.checkOutBy,
      cancellationHours: cancellationHours ?? this.cancellationHours,
      allowLateCheckout: allowLateCheckout ?? this.allowLateCheckout,
      notes: notes ?? this.notes,
    );
  }
}

/// A message between a guest and the accommodation agent.
class GuestMessage {
  const GuestMessage({
    required this.id,
    required this.bookingId,
    required this.sender,
    required this.body,
    required this.sentAt,
  });

  final String id;
  final String bookingId;

  /// `guest` or `agent`.
  final String sender;
  final String body;
  final DateTime sentAt;
}

class WalkInReservation {
  const WalkInReservation({
    required this.id,
    required this.roomId,
    required this.guestName,
    required this.checkIn,
    required this.checkOut,
    required this.status,
    required this.paymentStatus,
    required this.priceTzs,
    this.roomSegments = const [],
  });

  final String id;
  final String roomId;
  final String guestName;
  final DateTime checkIn;
  final DateTime checkOut;
  final String status;
  final String paymentStatus;
  final int priceTzs;
  final List<WalkInRoomSegment> roomSegments;

  factory WalkInReservation.fromJson(Map<String, dynamic> json) =>
      WalkInReservation(
        id: json['id'] as String,
        roomId: json['roomId'] as String,
        guestName: json['guestName'] as String,
        checkIn: DateTime.parse(json['checkIn'] as String).toLocal(),
        checkOut: DateTime.parse(json['checkOut'] as String).toLocal(),
        status: json['status'] as String,
        paymentStatus: json['paymentStatus'] as String,
        priceTzs: (json['priceTzs'] as num).toInt(),
        roomSegments: (json['roomSegments'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(WalkInRoomSegment.fromJson)
            .toList(growable: false),
      );
}

class WalkInRoomSegment {
  const WalkInRoomSegment({
    required this.roomId,
    required this.roomNumber,
    required this.startAt,
    required this.endAt,
  });

  final String roomId;
  final String roomNumber;
  final DateTime startAt;
  final DateTime endAt;

  factory WalkInRoomSegment.fromJson(Map<String, dynamic> json) {
    final room = json['room'];
    return WalkInRoomSegment(
      roomId: json['roomId'] as String,
      roomNumber: room is Map<String, dynamic>
          ? room['roomNumber'] as String? ?? 'unknown'
          : 'unknown',
      startAt: DateTime.parse(json['startAt'] as String).toLocal(),
      endAt: DateTime.parse(json['endAt'] as String).toLocal(),
    );
  }
}
