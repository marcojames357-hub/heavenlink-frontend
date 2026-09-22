import '../../payments/domain/payment_gateway.dart';

enum PropertyBusinessModel { bookable, contactUnlock }

enum PropertyCategory {
  hotel,
  lodge,
  servicedApartment,
  shortStayApartment,
  house,
  room,
  sharedAccommodation,
}

/// Moderation state of a listing.
///
/// Only [published] listings are visible in public search; everything else is
/// confined to the owning agent and the administrators.
enum ListingStatus {
  draft('Draft'),
  pendingReview('Awaiting approval'),
  published('Published'),
  paused('Paused'),
  rejected('Rejected');

  const ListingStatus(this.label);

  final String label;

  bool get isVisibleToCustomers => this == ListingStatus.published;
}

enum VerificationStatus { unverified, pending, verified }

enum BookingStatus { active, pending, completed, cancelled }

class Property {
  const Property({
    required this.id,
    required this.name,
    required this.city,
    required this.neighborhood,
    required this.priceTzs,
    required this.businessModel,
    required this.category,
    required this.imageUrl,
    required this.rating,
    required this.reviewCount,
    required this.bedrooms,
    required this.bathrooms,
    required this.amenities,
    required this.description,
    required this.available,
    required this.furnished,
    required this.parking,
    required this.water,
    required this.electricity,
    required this.security,
    required this.propertyVerification,
    required this.ownerVerification,
    required this.managerName,
    this.listingStatus = ListingStatus.published,
    this.agentId = '',
    this.imageUrls = const [],
    this.rentalPeriod = 'month',
    this.reportedCount = 0,
  });

  final String id;
  final String name;
  final String city;
  final String neighborhood;
  final int priceTzs;
  final PropertyBusinessModel businessModel;
  final PropertyCategory category;
  final String imageUrl;

  /// Extra photographs in addition to [imageUrl].
  final List<String> imageUrls;
  final double rating;
  final int reviewCount;
  final int bedrooms;
  final int bathrooms;
  final List<String> amenities;
  final String description;
  final bool available;
  final bool furnished;
  final bool parking;
  final bool water;
  final bool electricity;
  final bool security;
  final VerificationStatus propertyVerification;
  final VerificationStatus ownerVerification;
  final String managerName;

  /// Moderation state; only [ListingStatus.published] appears publicly.
  final ListingStatus listingStatus;

  /// Account that manages this listing, used for portal ownership checks.
  final String agentId;

  /// Billing period for rentals: `month`, `week` or `year`.
  final String rentalPeriod;

  /// Number of customer reports; administrators triage these.
  final int reportedCount;

  bool get isVerified =>
      propertyVerification == VerificationStatus.verified &&
      ownerVerification == VerificationStatus.verified;

  bool get isPublic => listingStatus.isVisibleToCustomers;

  bool get hasValidBusinessModel => switch (businessModel) {
    PropertyBusinessModel.bookable =>
      category == PropertyCategory.hotel ||
          category == PropertyCategory.lodge ||
          category == PropertyCategory.servicedApartment ||
          category == PropertyCategory.shortStayApartment,
    PropertyBusinessModel.contactUnlock =>
      category == PropertyCategory.house ||
          category == PropertyCategory.room ||
          category == PropertyCategory.sharedAccommodation,
  };

  /// Every photograph for this listing.
  List<String> get allPhotos => [imageUrl, ...imageUrls];

  String get generalLocation => '$neighborhood, $city';
  String get pricePeriod => businessModel == PropertyBusinessModel.bookable
      ? ' / night'
      : ' / $rentalPeriod';

  Property copyWith({
    String? name,
    String? city,
    String? neighborhood,
    int? priceTzs,
    PropertyCategory? category,
    String? imageUrl,
    List<String>? imageUrls,
    double? rating,
    int? reviewCount,
    int? bedrooms,
    int? bathrooms,
    List<String>? amenities,
    String? description,
    bool? available,
    bool? furnished,
    bool? parking,
    bool? water,
    bool? electricity,
    bool? security,
    String? managerName,
    ListingStatus? listingStatus,
    String? agentId,
    String? rentalPeriod,
    int? reportedCount,
  }) {
    return Property(
      id: id,
      name: name ?? this.name,
      city: city ?? this.city,
      neighborhood: neighborhood ?? this.neighborhood,
      priceTzs: priceTzs ?? this.priceTzs,
      businessModel: businessModel,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      imageUrls: imageUrls ?? this.imageUrls,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      bedrooms: bedrooms ?? this.bedrooms,
      bathrooms: bathrooms ?? this.bathrooms,
      amenities: amenities ?? this.amenities,
      description: description ?? this.description,
      available: available ?? this.available,
      furnished: furnished ?? this.furnished,
      parking: parking ?? this.parking,
      water: water ?? this.water,
      electricity: electricity ?? this.electricity,
      security: security ?? this.security,
      propertyVerification: propertyVerification,
      ownerVerification: ownerVerification,
      managerName: managerName ?? this.managerName,
      listingStatus: listingStatus ?? this.listingStatus,
      agentId: agentId ?? this.agentId,
      rentalPeriod: rentalPeriod ?? this.rentalPeriod,
      reportedCount: reportedCount ?? this.reportedCount,
    );
  }
}

class UnlockedProperty {
  const UnlockedProperty({required this.property, required this.unlockedAt});

  final Property property;
  final DateTime unlockedAt;
}

class Booking {
  const Booking({
    required this.id,
    required this.property,
    required this.checkIn,
    required this.checkOut,
    required this.guestName,
    required this.subtotalTzs,
    required this.feeTzs,
    required this.totalTzs,
    required this.createdAt,
    this.status = BookingStatus.active,
    this.paymentTransactionId,
  });

  final String id;
  final Property property;
  final DateTime checkIn;
  final DateTime checkOut;
  final String guestName;
  final int subtotalTzs;
  final int feeTzs;
  final int totalTzs;
  final DateTime createdAt;
  final BookingStatus status;

  /// Verified payment that confirmed this reservation.
  final String? paymentTransactionId;
}

class PaymentRecord {
  const PaymentRecord({
    required this.reference,
    required this.property,
    required this.amountTzs,
    required this.purpose,
    required this.method,
    required this.createdAt,
    this.status,
    this.paymentTransactionId,
  });

  final String reference;
  final Property property;
  final int amountTzs;
  final String purpose;
  final String method;
  final DateTime createdAt;
  final PaymentTransactionStatus? status;
  final String? paymentTransactionId;
}

class OwnerContact {
  const OwnerContact({
    required this.exactAddress,
    required this.contactName,
    required this.role,
    required this.phone,
    required this.whatsApp,
    required this.latitude,
    required this.longitude,
  });

  final String exactAddress;
  final String contactName;
  final String role;
  final String phone;
  final String whatsApp;
  final double latitude;
  final double longitude;
}
