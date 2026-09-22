import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env_config.dart';
import '../domain/property.dart';

/// Data access for property listings.
///
/// `getAuthorizedContact` is the only way to read a protected contact and
/// callers must already hold an active unlock record. It is deliberately kept
/// apart from `getProperties` so protected data can never ride along in a
/// public listing response.
abstract interface class PropertyRepository {
  /// Every listing, including drafts, paused and rejected ones.
  Future<List<Property>> getProperties();

  Future<OwnerContact?> getAuthorizedContact(String propertyId);

  Future<Set<String>> getSavedPropertyIds();

  Future<void> setSavedProperty(String propertyId, bool saved);

  /// Creates or replaces a listing.
  Future<Property> save(Property property);

  Future<void> delete(String propertyId);

  Future<void> updateStatus(String propertyId, ListingStatus status);

  Future<void> incrementReportCount(String propertyId);
}

class HttpPropertyRepository implements PropertyRepository {
  HttpPropertyRepository({
    required this._tokenProvider,
    required this._roleProvider,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String? Function() _tokenProvider;
  final String? Function() _roleProvider;
  final http.Client _client;
  final Set<String> _knownIds = {};

  @override
  Future<Set<String>> getSavedPropertyIds() async {
    final result = await _request(
      'GET',
      '/api/v1/properties/favorites',
      authenticated: true,
    );
    return (result['favorites'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((favorite) => favorite['listingId'] as String)
        .toSet();
  }

  @override
  Future<void> setSavedProperty(String propertyId, bool saved) async {
    await _request(
      saved ? 'PUT' : 'DELETE',
      '/api/v1/properties/${Uri.encodeComponent(propertyId)}/favorite',
      authenticated: true,
      body: saved ? const {} : null,
    );
  }

  @override
  Future<List<Property>> getProperties() async {
    final token = _tokenProvider();
    final role = _roleProvider();
    final path = role == 'ADMIN'
        ? '/api/v1/admin/properties'
        : role == 'RENTAL_AGENT' || role == 'STAY_AGENT'
        ? '/api/v1/agents/listings'
        : '/api/v1/properties';
    final result = await _request('GET', path, token: token);
    final records =
        (result['properties'] ?? result['listings']) as List<dynamic>? ??
        const [];
    final properties = records
        .whereType<Map<String, dynamic>>()
        .map(_propertyFromJson)
        .toList(growable: false);
    _knownIds
      ..clear()
      ..addAll(properties.map((property) => property.id));
    return properties;
  }

  @override
  Future<OwnerContact?> getAuthorizedContact(String propertyId) async {
    final result = await _request(
      'GET',
      '/api/v1/properties/${Uri.encodeComponent(propertyId)}/contact',
      authenticated: true,
    );
    final json = result['contact'];
    if (json is! Map<String, dynamic>) return null;
    return OwnerContact(
      exactAddress: json['exactAddress'] as String? ?? '',
      contactName: json['contactName'] as String? ?? '',
      role: json['role'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      whatsApp: json['whatsApp'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Future<Property> save(Property property) async {
    final isExisting = _knownIds.contains(property.id);
    final path = isExisting
        ? '/api/v1/properties/${Uri.encodeComponent(property.id)}'
        : '/api/v1/properties';
    final result = await _request(
      isExisting ? 'PUT' : 'POST',
      path,
      authenticated: true,
      body: _propertyToJson(property, includeId: isExisting),
    );
    final json = result['property'];
    if (json is! Map<String, dynamic>) {
      throw StateError('The server did not return the saved listing.');
    }
    final saved = _propertyFromJson(json);
    _knownIds.add(saved.id);
    return saved;
  }

  @override
  Future<void> delete(String propertyId) async {
    await _request(
      'DELETE',
      '/api/v1/properties/${Uri.encodeComponent(propertyId)}',
      authenticated: true,
    );
    _knownIds.remove(propertyId);
  }

  @override
  Future<void> updateStatus(String propertyId, ListingStatus status) async {
    await _request(
      'PATCH',
      '/api/v1/properties/${Uri.encodeComponent(propertyId)}/status',
      authenticated: true,
      body: {'status': status.name},
    );
  }

  @override
  Future<void> incrementReportCount(String propertyId) async {
    await _request(
      'POST',
      '/api/v1/properties/${Uri.encodeComponent(propertyId)}/report',
      authenticated: true,
      body: const {},
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? token,
    bool authenticated = false,
  }) async {
    final activeToken = token ?? _tokenProvider();
    if (authenticated && (activeToken == null || activeToken.isEmpty)) {
      throw StateError('Sign in to use this Haven Link feature.');
    }
    try {
      final request = http.Request(method, EnvConfig.endpoint(path))
        ..headers['content-type'] = 'application/json';
      if (activeToken != null && activeToken.isNotEmpty) {
        request.headers['authorization'] = 'Bearer $activeToken';
      }
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
        throw StateError(message ?? 'The listing request was rejected.');
      }
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError(
        'We could not reach Haven Link listings. Check your connection.',
      );
    }
  }

  Property _propertyFromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, Object? value, T fallback) =>
        values.firstWhere((item) => item.name == value, orElse: () => fallback);
    final imageUrls = (json['imageUrls'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    return Property(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      city: json['city'] as String? ?? '',
      neighborhood: json['neighborhood'] as String? ?? '',
      priceTzs: (json['priceTzs'] as num?)?.toInt() ?? 0,
      businessModel: enumValue(
        PropertyBusinessModel.values,
        json['businessModel'],
        PropertyBusinessModel.contactUnlock,
      ),
      category: enumValue(
        PropertyCategory.values,
        json['category'],
        PropertyCategory.house,
      ),
      imageUrl: json['imageUrl'] as String? ?? '',
      imageUrls: imageUrls,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      bedrooms: (json['bedrooms'] as num?)?.toInt() ?? 0,
      bathrooms: (json['bathrooms'] as num?)?.toInt() ?? 0,
      amenities: (json['amenities'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      description: json['description'] as String? ?? '',
      available: json['available'] as bool? ?? true,
      furnished: json['furnished'] as bool? ?? false,
      parking: json['parking'] as bool? ?? false,
      water: json['water'] as bool? ?? false,
      electricity: json['electricity'] as bool? ?? false,
      security: json['security'] as bool? ?? false,
      propertyVerification: enumValue(
        VerificationStatus.values,
        json['propertyVerification'],
        VerificationStatus.unverified,
      ),
      ownerVerification: enumValue(
        VerificationStatus.values,
        json['ownerVerification'],
        VerificationStatus.unverified,
      ),
      managerName: json['managerName'] as String? ?? '',
      listingStatus: enumValue(
        ListingStatus.values,
        json['listingStatus'],
        ListingStatus.published,
      ),
      agentId: json['agentId'] as String? ?? '',
      rentalPeriod: json['rentalPeriod'] as String? ?? 'month',
      reportedCount: (json['reportedCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> _propertyToJson(
    Property property, {
    required bool includeId,
  }) => {
    if (includeId) 'id': property.id,
    'name': property.name,
    'city': property.city,
    'neighborhood': property.neighborhood,
    'priceTzs': property.priceTzs,
    'businessModel': property.businessModel.name,
    'category': property.category.name,
    'imageUrl': property.imageUrl,
    'imageUrls': property.imageUrls,
    'bedrooms': property.bedrooms,
    'bathrooms': property.bathrooms,
    'amenities': property.amenities,
    'description': property.description,
    'available': property.available,
    'furnished': property.furnished,
    'parking': property.parking,
    'water': property.water,
    'electricity': property.electricity,
    'security': property.security,
    'managerName': property.managerName,
    'rentalPeriod': property.rentalPeriod,
  };
}

class UnconfiguredPropertyRepository implements PropertyRepository {
  const UnconfiguredPropertyRepository();

  StateError _unavailable() =>
      StateError('Property listings require a configured Haven Link backend.');

  @override
  Future<List<Property>> getProperties() async => throw _unavailable();

  @override
  Future<OwnerContact?> getAuthorizedContact(String propertyId) async =>
      throw _unavailable();

  @override
  Future<Set<String>> getSavedPropertyIds() async => throw _unavailable();

  @override
  Future<void> setSavedProperty(String propertyId, bool saved) async =>
      throw _unavailable();

  @override
  Future<Property> save(Property property) async => throw _unavailable();

  @override
  Future<void> delete(String propertyId) async => throw _unavailable();

  @override
  Future<void> updateStatus(String propertyId, ListingStatus status) async =>
      throw _unavailable();

  @override
  Future<void> incrementReportCount(String propertyId) async =>
      throw _unavailable();
}

PropertyRepository resolvePropertyRepository({
  required String? Function() tokenProvider,
  required String? Function() roleProvider,
}) {
  if (EnvConfig.backendConfigured) {
    return HttpPropertyRepository(
      tokenProvider: tokenProvider,
      roleProvider: roleProvider,
    );
  }
  if (kDebugMode) return MockPropertyRepository();
  return const UnconfiguredPropertyRepository();
}

class MockPropertyRepository implements PropertyRepository {
  MockPropertyRepository() : _properties = _seedWithOwnership();

  /// Demo agent accounts that own the seeded listings.
  static const String kRentalAgentId = 'agent-rental-1';
  static const String kStayAgentId = 'agent-stay-1';

  static const List<Property> _base = [
    Property(
      id: 'stay-01',
      name: 'The Oyster Bay House',
      city: 'Dar es Salaam',
      neighborhood: 'Oyster Bay',
      priceTzs: 800000,
      businessModel: PropertyBusinessModel.bookable,
      category: PropertyCategory.servicedApartment,
      imageUrl:
          'https://images.unsplash.com/photo-1600210492486-724fe5c67fb0?w=1200&auto=format&fit=crop',
      rating: 4.9,
      reviewCount: 38,
      bedrooms: 2,
      bathrooms: 2,
      amenities: ['Wi-Fi', 'Pool', 'Air conditioning', 'Breakfast'],
      description:
          'A calm, design-led stay in the heart of Oyster Bay, with generous living spaces and attentive on-site hosting.',
      available: true,
      furnished: true,
      parking: true,
      water: true,
      electricity: true,
      security: true,
      propertyVerification: VerificationStatus.verified,
      ownerVerification: VerificationStatus.verified,
      managerName: 'Haven Stay Team',
    ),
    Property(
      id: 'stay-02',
      name: 'Masaki Palm Lodge',
      city: 'Dar es Salaam',
      neighborhood: 'Masaki',
      priceTzs: 320000,
      businessModel: PropertyBusinessModel.bookable,
      category: PropertyCategory.lodge,
      imageUrl:
          'https://images.unsplash.com/photo-1611892440504-42a792e24d32?w=1200&auto=format&fit=crop',
      rating: 4.7,
      reviewCount: 24,
      bedrooms: 1,
      bathrooms: 1,
      amenities: ['Wi-Fi', 'Garden', 'Airport transfer'],
      description:
          'A leafy boutique lodge close to the waterfront, local dining and the city’s business district.',
      available: true,
      furnished: true,
      parking: true,
      water: true,
      electricity: true,
      security: true,
      propertyVerification: VerificationStatus.verified,
      ownerVerification: VerificationStatus.verified,
      managerName: 'Neema M.',
    ),
    Property(
      id: 'rent-01',
      name: 'Bright Mbezi Beach Home',
      city: 'Dar es Salaam',
      neighborhood: 'Mbezi Beach',
      priceTzs: 650000,
      businessModel: PropertyBusinessModel.contactUnlock,
      category: PropertyCategory.house,
      imageUrl:
          'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?w=1200&auto=format&fit=crop',
      rating: 4.8,
      reviewCount: 12,
      bedrooms: 2,
      bathrooms: 2,
      amenities: ['Parking', 'Water tank', 'Electricity', 'Security'],
      description:
          'A bright, unfurnished family home in a quiet part of Mbezi Beach, with reliable utilities and a private garden.',
      available: true,
      furnished: false,
      parking: true,
      water: true,
      electricity: true,
      security: true,
      propertyVerification: VerificationStatus.verified,
      ownerVerification: VerificationStatus.verified,
      managerName: 'Verified owner',
    ),
    Property(
      id: 'rent-02',
      name: 'Sinza Self-Contained Room',
      city: 'Dar es Salaam',
      neighborhood: 'Sinza',
      priceTzs: 280000,
      businessModel: PropertyBusinessModel.contactUnlock,
      category: PropertyCategory.room,
      imageUrl:
          'https://images.unsplash.com/photo-1616486338812-3dadae4b4ace?w=1200&auto=format&fit=crop',
      rating: 4.5,
      reviewCount: 8,
      bedrooms: 1,
      bathrooms: 1,
      amenities: ['Water', 'Electricity', 'Security', 'Tiled floors'],
      description:
          'A neat self-contained room with a private bathroom, convenient to daladala routes and everyday shops.',
      available: true,
      furnished: false,
      parking: false,
      water: true,
      electricity: true,
      security: true,
      propertyVerification: VerificationStatus.pending,
      ownerVerification: VerificationStatus.verified,
      managerName: 'Verified agent',
    ),
    Property(
      id: 'rent-03',
      name: 'Kinondoni Garden Apartment',
      city: 'Dar es Salaam',
      neighborhood: 'Kinondoni',
      priceTzs: 950000,
      businessModel: PropertyBusinessModel.contactUnlock,
      category: PropertyCategory.house,
      imageUrl:
          'https://images.unsplash.com/photo-1600566753086-00f18fb6b3ea?w=1200&auto=format&fit=crop',
      rating: 4.6,
      reviewCount: 15,
      bedrooms: 3,
      bathrooms: 2,
      amenities: ['Garden', 'Parking', 'Water', 'Security'],
      description:
          'A spacious unfurnished apartment with a shaded garden and easy access to central Kinondoni.',
      available: true,
      furnished: false,
      parking: true,
      water: true,
      electricity: true,
      security: true,
      propertyVerification: VerificationStatus.verified,
      ownerVerification: VerificationStatus.pending,
      managerName: 'Property manager',
    ),
    Property(
      id: 'stay-03',
      name: 'Arusha Highland Retreat',
      city: 'Arusha',
      neighborhood: 'Njiro',
      priceTzs: 420000,
      businessModel: PropertyBusinessModel.bookable,
      category: PropertyCategory.hotel,
      imageUrl:
          'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=1200&auto=format&fit=crop',
      rating: 4.9,
      reviewCount: 51,
      bedrooms: 1,
      bathrooms: 1,
      amenities: ['Restaurant', 'Garden', 'Wi-Fi', 'Airport transfer'],
      description:
          'A welcoming highland hideaway with a garden restaurant and easy access to Arusha’s city centre.',
      available: true,
      furnished: true,
      parking: true,
      water: true,
      electricity: true,
      security: true,
      propertyVerification: VerificationStatus.verified,
      ownerVerification: VerificationStatus.verified,
      managerName: 'Asha, property manager',
    ),
  ];

  static const Map<String, OwnerContact> _authorizedContacts = {
    'rent-01': OwnerContact(
      exactAddress: 'Plot 18, Bahari Road, Mbezi Beach, Dar es Salaam',
      contactName: 'Mariam Joseph',
      role: 'Verified property owner',
      phone: '+255 754 000 111',
      whatsApp: '+255754000111',
      latitude: -6.7088,
      longitude: 39.2252,
    ),
    'rent-02': OwnerContact(
      exactAddress: 'House 7, Mbuyuni Street, Sinza, Dar es Salaam',
      contactName: 'Juma Kweka',
      role: 'Authorized property agent',
      phone: '+255 713 000 222',
      whatsApp: '+255713000222',
      latitude: -6.7791,
      longitude: 39.2217,
    ),
    'rent-03': OwnerContact(
      exactAddress: 'Apartment 4, Garden Lane, Kinondoni, Dar es Salaam',
      contactName: 'Rehema Said',
      role: 'Verified property owner',
      phone: '+255 687 000 333',
      whatsApp: '+255687000333',
      latitude: -6.7853,
      longitude: 39.2661,
    ),
    'rent-04': OwnerContact(
      exactAddress: 'Block C, Mwai Kibaki Road, Ubungo, Dar es Salaam',
      contactName: 'Hassan Mrisho',
      role: 'Authorized property agent',
      phone: '+255 765 000 444',
      whatsApp: '+255765000444',
      latitude: -6.7809,
      longitude: 39.2441,
    ),
  };

  final List<Property> _properties;
  final Set<String> _savedPropertyIds = {};

  @override
  Future<Set<String>> getSavedPropertyIds() async => Set.of(_savedPropertyIds);

  @override
  Future<void> setSavedProperty(String propertyId, bool saved) async {
    if (saved) {
      _savedPropertyIds.add(propertyId);
    } else {
      _savedPropertyIds.remove(propertyId);
    }
  }

  static List<Property> _seedWithOwnership() {
    final seeded = _base
        .map(
          (property) => property.copyWith(
            agentId: property.businessModel == PropertyBusinessModel.bookable
                ? kStayAgentId
                : kRentalAgentId,
          ),
        )
        .toList();
    // A listing submitted for review, hidden from customers until approved.
    seeded.add(
      const Property(
        id: 'rent-04',
        name: 'Ubungo One-Room Studio',
        city: 'Dar es Salaam',
        neighborhood: 'Ubungo',
        priceTzs: 220000,
        businessModel: PropertyBusinessModel.contactUnlock,
        category: PropertyCategory.room,
        imageUrl:
            'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?w=1200&auto=format&fit=crop',
        rating: 0,
        reviewCount: 0,
        bedrooms: 1,
        bathrooms: 1,
        amenities: ['Water', 'Electricity'],
        description:
            'A neat one-room studio near Ubungo junction, suitable for a single occupant.',
        available: true,
        furnished: false,
        parking: false,
        water: true,
        electricity: true,
        security: false,
        propertyVerification: VerificationStatus.unverified,
        ownerVerification: VerificationStatus.unverified,
        managerName: 'Haven Link agent',
        agentId: kRentalAgentId,
        listingStatus: ListingStatus.pendingReview,
      ),
    );
    return seeded;
  }

  @override
  Future<List<Property>> getProperties() async =>
      List.unmodifiable(List.of(_properties));

  @override
  Future<OwnerContact?> getAuthorizedContact(String propertyId) async =>
      _authorizedContacts[propertyId];

  @override
  Future<Property> save(Property property) async {
    final index = _properties.indexWhere((item) => item.id == property.id);
    if (index == -1) {
      _properties.add(property);
    } else {
      _properties[index] = property;
    }
    return property;
  }

  @override
  Future<void> delete(String propertyId) async {
    _properties.removeWhere((item) => item.id == propertyId);
  }

  @override
  Future<void> updateStatus(String propertyId, ListingStatus status) async {
    final index = _properties.indexWhere((item) => item.id == propertyId);
    if (index == -1) return;
    _properties[index] = _properties[index].copyWith(listingStatus: status);
  }

  @override
  Future<void> incrementReportCount(String propertyId) async {
    final index = _properties.indexWhere((item) => item.id == propertyId);
    if (index == -1) return;
    _properties[index] = _properties[index].copyWith(
      reportedCount: _properties[index].reportedCount + 1,
    );
  }
}
