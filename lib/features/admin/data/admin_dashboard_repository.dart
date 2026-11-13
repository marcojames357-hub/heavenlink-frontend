import '../../../core/data/api_client.dart';

class AdminDashboardSummary {
  const AdminDashboardSummary({
    required this.totalUsers,
    required this.totalProperties,
    required this.totalBookings,
    required this.totalRevenueTzs,
  });

  final int totalUsers;
  final int totalProperties;
  final int totalBookings;
  final int totalRevenueTzs;

  factory AdminDashboardSummary.fromJson(Map<String, dynamic> json) {
    final users = _requiredObject(json['users'], 'users');
    final properties = _requiredObject(json['properties'], 'properties');
    final bookings = _requiredObject(json['bookings'], 'bookings');
    final transactions = _requiredObject(json['transactions'], 'transactions');
    return AdminDashboardSummary(
      totalUsers: _requiredInt(users['total'], 'users.total'),
      totalProperties: _requiredInt(properties['total'], 'properties.total'),
      totalBookings: _requiredInt(bookings['total'], 'bookings.total'),
      totalRevenueTzs: _requiredInt(
        transactions['totalRevenue'],
        'transactions.totalRevenue',
      ),
    );
  }
}

class AdminAuditEvent {
  const AdminAuditEvent({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.actorName,
    required this.createdAt,
    required this.metadata,
  });

  final String id;
  final String action;
  final String entityType;
  final String entityId;
  final String actorName;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  factory AdminAuditEvent.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'];
    final rawMetadata = json['metadata'];
    final createdAt = json['createdAt'];
    if (actor != null && actor is! Map<String, dynamic>) {
      throw StateError('The audit event actor is invalid.');
    }
    if (rawMetadata is! Map<String, dynamic>) {
      throw StateError('The audit event metadata is invalid.');
    }
    if (createdAt is! String) {
      throw StateError('The audit event timestamp is missing.');
    }
    return AdminAuditEvent(
      id: _requiredString(json['id'], 'id'),
      action: _requiredString(json['action'], 'action'),
      entityType: _requiredString(json['entityType'], 'entityType'),
      entityId: _requiredString(json['entityId'], 'entityId'),
      actorName: actor == null
          ? 'Unknown administrator'
          : (actor['fullName'] as String? ?? 'Unknown administrator'),
      createdAt: DateTime.parse(createdAt),
      metadata: Map<String, dynamic>.unmodifiable(rawMetadata),
    );
  }
}

class AdminDashboardRepository {
  AdminDashboardRepository({
    required String? Function() tokenProvider,
    ApiClient? api,
  }) : _api = api ?? ApiClient(tokenProvider: tokenProvider);

  final ApiClient _api;

  Future<AdminDashboardSummary> loadSummary() async {
    final response = await _api.get('/api/v1/admin/dashboard');
    return AdminDashboardSummary.fromJson(
      _requiredObject(response['stats'], 'stats'),
    );
  }

  Future<List<AdminAuditEvent>> loadAuditEvents({int limit = 100}) async {
    if (limit < 1 || limit > 200) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 200.');
    }
    final query = Uri(queryParameters: {'limit': '$limit'}).query;
    final response = await _api.get('/api/v1/admin/audit-events?$query');
    final events = response['events'];
    if (events is! List) {
      throw StateError('The server returned an invalid audit event list.');
    }
    return events
        .whereType<Map<String, dynamic>>()
        .map(AdminAuditEvent.fromJson)
        .toList(growable: false);
  }
}

Map<String, dynamic> _requiredObject(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw StateError('The dashboard response is missing $field.');
}

int _requiredInt(Object? value, String field) {
  if (value is num) return value.toInt();
  throw StateError('The dashboard response is missing $field.');
}

String _requiredString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw StateError('The audit event is missing $field.');
}
