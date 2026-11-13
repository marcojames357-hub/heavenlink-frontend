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
  Future<Property> save(
    Property property, {
    bool confirmInventoryModelChange = false,
    bool saveAsDraft = false,
  });

  Future<void> delete(String propertyId);

  Future<void> updateStatus(String propertyId, ListingStatus status);

  Future<void> incrementReportCount(String propertyId);

  /// Uploads listing photos and returns their public https URLs.
  Future<List<String>> uploadPhotos(
    List<({String name, List<int> bytes})> files,
  );
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
      latitude: _asDouble(json['latitude']) ?? 0,
      longitude: _asDouble(json['longitude']) ?? 0,
    );
  }

  @override
  Future<Property> save(
    Property property, {
    bool confirmInventoryModelChange = false,
    bool saveAsDraft = false,
  }) async {
    final isExisting = _knownIds.contains(property.id);
    final path = isExisting
        ? '/api/v1/properties/${Uri.encodeComponent(property.id)}'
        : '/api/v1/properties';
    final result = await _request(
      isExisting ? 'PUT' : 'POST',
      path,
      authenticated: true,
      body: {
        ..._propertyToJson(property, includeId: isExisting),
        if (confirmInventoryModelChange) 'confirmInventoryModelChange': true,
        if (!isExisting && saveAsDraft) 'saveAsDraft': true,
      },
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

  @override
  Future<List<String>> uploadPhotos(
    List<({String name, List<int> bytes})> files,
  ) async {
    final token = _tokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in to upload photos.');
    }
    try {
      final request =
          http.MultipartRequest(
              'POST',
              EnvConfig.endpoint('/api/v1/properties/photos'),
            )
            ..headers['authorization'] = '******'
            ..files.addAll([
              for (final file in files)
                http.MultipartFile.fromBytes(
                  'photos',
                  file.bytes,
                  filename: file.name,
                ),
            ]);
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      if (response.statusCode >= 400) {
        final message = decoded is Map<String, dynamic>
            ? decoded['message'] as String? ?? decoded['error'] as String?
            : null;
        throw StateError(message ?? 'The photos were rejected.');
      }
      return ((decoded as Map<String, dynamic>)['urls'] as List<dynamic>? ??
              const [])
          .whereType<String>()
          .toList(growable: false);
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError(
        'We could not upload the photos. Check your connection.',
      );
    }
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
        json['accommodationType'] ?? json['category'],
        PropertyCategory.house,
      ),
      imageUrl: json['imageUrl'] as String? ?? '',
      imageUrls: imageUrls,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
      bedrooms: (json['bedrooms'] as num?)?.toInt() ?? 0,
      bathrooms: (json['bathrooms'] as num?)?.toInt() ?? 0,
      maxGuests: (json['maxGuests'] as num?)?.toInt(),
      stayRules: json['stayRules'] is Map<String, dynamic>
          ? StayRules.fromJson(json['stayRules'] as Map<String, dynamic>)
          : null,
      amenities: (json['amenities'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      amenityDetails: (json['amenityDetails'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AmenityDetail.fromJson)
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
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      formattedAddress: json['formattedAddress'] as String?,
      locationVerification: enumValue(
        VerificationStatus.values,
        json['locationVerification'],
        VerificationStatus.unverified,
      ),
      locationVisibility: enumValue(
        LocationVisibility.values,
        json['locationVisibility'],
        LocationVisibility.approximate,
      ),
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
    'category': property.category == PropertyCategory.motel
        ? PropertyCategory.hotel.name
        : property.category.name,
    if ([
      PropertyCategory.hotel,
      PropertyCategory.motel,
      PropertyCategory.lodge,
    ].contains(property.category))
      'accommodationType': property.category.name,
    'imageUrl': property.imageUrl,
    'imageUrls': property.imageUrls,
    'bedrooms': property.bedrooms,
    'bathrooms': property.bathrooms,
    if (property.category.isApartmentStay) ...{
      'maxGuests': property.maxGuests,
      'stayRules': property.stayRules?.toJson(),
    },
    'amenities': property.amenities,
    'amenityDetails': property.amenityDetails
        .map((amenity) => amenity.toJson())
        .toList(growable: false),
    'description': property.description,
    'available': property.available,
    'furnished': property.furnished,
    'parking': property.parking,
    'water': property.water,
    'electricity': property.electricity,
    'security': property.security,
    'managerName': property.managerName,
    'rentalPeriod': property.rentalPeriod,
    'latitude': property.latitude,
    'longitude': property.longitude,
    'formattedAddress': property.formattedAddress,
    'locationVisibility': property.locationVisibility.name,
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
  Future<Property> save(
    Property property, {
    bool confirmInventoryModelChange = false,
    bool saveAsDraft = false,
  }) async => throw _unavailable();

  @override
  Future<void> delete(String propertyId) async => throw _unavailable();

  @override
  Future<void> updateStatus(String propertyId, ListingStatus status) async =>
      throw _unavailable();

  @override
  Future<void> incrementReportCount(String propertyId) async =>
      throw _unavailable();

  @override
  Future<List<String>> uploadPhotos(
    List<({String name, List<int> bytes})> files,
  ) async => throw _unavailable();
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
  MockPropertyRepository({
    List<Property> properties = const [],
    Map<String, OwnerContact> authorizedContacts = const {},
  }) : _properties = List.of(properties),
       _authorizedContacts = Map.of(authorizedContacts);

  final List<Property> _properties;
  final Map<String, OwnerContact> _authorizedContacts;
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

  @override
  Future<List<Property>> getProperties() async =>
      List.unmodifiable(List.of(_properties));

  @override
  Future<OwnerContact?> getAuthorizedContact(String propertyId) async =>
      _authorizedContacts[propertyId];

  @override
  Future<Property> save(
    Property property, {
    bool confirmInventoryModelChange = false,
    bool saveAsDraft = false,
  }) async {
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

  @override
  Future<List<String>> uploadPhotos(
    List<({String name, List<int> bytes})> files,
  ) async => throw StateError('Photo upload needs a configured backend.');
}

double? _asDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');
