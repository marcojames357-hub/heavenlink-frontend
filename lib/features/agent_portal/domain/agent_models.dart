import '../../payments/domain/unlock_record.dart';

/// A customer's completed contact unlock on an agent's listing.
class UnlockActivity {
  const UnlockActivity({required this.record, required this.listingName});

  final UnlockRecord record;
  final String listingName;
}

/// A customer question about a rental listing.
enum InquiryType { general, contactUnlock }

enum InquiryStatus { open, answered, closed }

class ListingInquiry {
  const ListingInquiry({
    required this.id,
    required this.listingId,
    required this.customerName,
    required this.message,
    required this.type,
    required this.createdAt,
    this.status = InquiryStatus.open,
    this.response,
  });

  final String id;
  final String listingId;
  final String customerName;
  final String message;
  final InquiryType type;
  final DateTime createdAt;
  final InquiryStatus status;
  final String? response;

  ListingInquiry copyWith({InquiryStatus? status, String? response}) {
    return ListingInquiry(
      id: id,
      listingId: listingId,
      customerName: customerName,
      message: message,
      type: type,
      createdAt: createdAt,
      status: status ?? this.status,
      response: response ?? this.response,
    );
  }
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
    this.description = '',
  });

  final String id;
  final String listingId;
  final String name;
  final int nightlyPriceTzs;
  final int capacity;
  final int totalRooms;
  final List<String> amenities;
  final String description;

  RoomType copyWith({
    String? name,
    int? nightlyPriceTzs,
    int? capacity,
    int? totalRooms,
    List<String>? amenities,
    String? description,
  }) {
    return RoomType(
      id: id,
      listingId: listingId,
      name: name ?? this.name,
      nightlyPriceTzs: nightlyPriceTzs ?? this.nightlyPriceTzs,
      capacity: capacity ?? this.capacity,
      totalRooms: totalRooms ?? this.totalRooms,
      amenities: amenities ?? this.amenities,
      description: description ?? this.description,
    );
  }
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
