import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/env_config.dart';
import '../domain/review_models.dart';

/// A file chosen by the guest, uploaded as multipart content.
typedef UploadFile = ({String name, List<int> bytes});

class ReviewRepository {
  ReviewRepository({required this.tokenProvider, http.Client? client})
    : _client = client ?? http.Client();

  final String? Function() tokenProvider;
  final http.Client _client;

  Future<List<TripBooking>> loadTrips() async {
    final result = await _request(
      'GET',
      '/api/v1/reviews/trips',
      authenticated: true,
    );
    return (result['trips'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TripBooking.fromJson)
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> loadNotifications() async {
    final result = await _request(
      'GET',
      '/api/v1/agents/notifications',
      authenticated: true,
    );
    return (result['notifications'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<GuestReview> submitReview({
    required String bookingId,
    required int overallRating,
    required Map<String, int> ratings,
    String? title,
    String? comment,
    List<UploadFile> photos = const [],
  }) async {
    final result = await _request(
      'POST',
      '/api/v1/reviews',
      authenticated: true,
      body: {
        'bookingId': bookingId,
        'overallRating': overallRating,
        ...ratings,
        'title': ?title,
        'comment': ?comment,
      },
      files: photos,
      fileField: 'photos',
    );
    return GuestReview.fromJson(result['review'] as Map<String, dynamic>);
  }

  Future<PropertyReviewPage> loadPropertyReviews({
    required String propertyId,
    int page = 1,
    String sort = 'newest',
    int? rating,
    String? category,
    bool withPhotos = false,
  }) async {
    final query = {'page': '$page', 'limit': '6', 'sort': sort};
    if (rating != null) query['rating'] = '$rating';
    if (category != null) query['category'] = category;
    if (withPhotos) query['withPhotos'] = 'true';
    final uri = EnvConfig.endpoint(
      '/api/v1/reviews/properties/${Uri.encodeComponent(propertyId)}',
    ).replace(queryParameters: query);
    final result = await _request('GET', uri.toString());
    return PropertyReviewPage.fromJson(result);
  }

  Future<void> reportReview({
    required String reviewId,
    required String reason,
  }) async {
    await _request(
      'POST',
      '/api/v1/reviews/${Uri.encodeComponent(reviewId)}/reports',
      authenticated: true,
      body: {'reason': reason},
    );
  }

  Future<ProblemReportItem> submitProblemReport({
    required String bookingId,
    required String category,
    required String severity,
    required String description,
    List<UploadFile> evidence = const [],
  }) async {
    final result = await _request(
      'POST',
      '/api/v1/reports',
      authenticated: true,
      body: {
        'bookingId': bookingId,
        'category': category,
        'severity': severity,
        'description': description,
      },
      files: evidence,
      fileField: 'evidence',
    );
    return ProblemReportItem.fromJson(result['report'] as Map<String, dynamic>);
  }

  Future<List<ProblemReportItem>> loadMyReports() =>
      _loadReports('/api/v1/reports/mine');

  Future<void> replyToMyReport(String reportId, String message) async {
    await _request(
      'POST',
      '/api/v1/reports/${Uri.encodeComponent(reportId)}/reply',
      authenticated: true,
      body: {'body': message},
    );
  }

  Future<Map<String, dynamic>> loadAgentReviews() =>
      _request('GET', '/api/v1/reviews/agent', authenticated: true);

  Future<void> respondToReview(String reviewId, String response) async {
    await _request(
      'POST',
      '/api/v1/reviews/${Uri.encodeComponent(reviewId)}/response',
      authenticated: true,
      body: {'response': response},
    );
  }

  Future<List<ProblemReportItem>> loadAgentReports() =>
      _loadReports('/api/v1/reports/agent');

  Future<void> replyAsAgent(
    String reportId,
    String message, {
    bool resolution = false,
  }) async {
    await _request(
      'POST',
      '/api/v1/reports/agent/${Uri.encodeComponent(reportId)}/reply',
      authenticated: true,
      body: {'body': message, 'kind': resolution ? 'resolution' : 'reply'},
    );
  }

  Future<({List<ProblemReportItem> reports, Map<String, int> stats})>
  loadAdminReports({
    String? category,
    String? severity,
    String? status,
    String? classification,
  }) async {
    final query = <String, String>{};
    if (category != null) query['category'] = category;
    if (severity != null) query['severity'] = severity;
    if (status != null) query['status'] = status;
    if (classification != null) query['classification'] = classification;
    final uri = EnvConfig.endpoint(
      '/api/v1/reports/admin',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final result = await _request('GET', uri.toString(), authenticated: true);
    final stats = result['stats'] as Map<String, dynamic>? ?? const {};
    return (
      reports: _parseReports(result),
      stats: {
        for (final entry in stats.entries)
          entry.key: (entry.value as num?)?.toInt() ?? 0,
      },
    );
  }

  Future<void> updateAdminReport(
    String reportId, {
    String? status,
    bool? sharedWithAgent,
    bool escalate = false,
    String? assignedStaffId,
  }) async {
    await _request(
      'PATCH',
      '/api/v1/reports/admin/${Uri.encodeComponent(reportId)}',
      authenticated: true,
      body: {
        'status': ?status,
        'sharedWithAgent': ?sharedWithAgent,
        if (escalate) 'escalate': true,
        'assignedStaffId': ?assignedStaffId,
      },
    );
  }

  Future<void> addAdminReportNote(
    String reportId,
    String message,
    String visibility,
  ) async {
    await _request(
      'POST',
      '/api/v1/reports/admin/${Uri.encodeComponent(reportId)}/notes',
      authenticated: true,
      body: {'body': message, 'visibility': visibility},
    );
  }

  Future<Map<String, dynamic>> loadAdminReviews({
    String? status,
    bool reportedOnly = false,
    int page = 1,
    String? propertyId,
    String? agentId,
    String? from,
    String? to,
  }) {
    final queryParameters = <String, String>{'page': '$page'};
    if (status != null) queryParameters['status'] = status;
    if (reportedOnly) queryParameters['reportedOnly'] = 'true';
    if (propertyId != null && propertyId.isNotEmpty) {
      queryParameters['propertyId'] = propertyId;
    }
    if (agentId != null && agentId.isNotEmpty) {
      queryParameters['agentId'] = agentId;
    }
    if (from != null) queryParameters['from'] = from;
    if (to != null) queryParameters['to'] = to;
    final uri = EnvConfig.endpoint(
      '/api/v1/admin/reviews',
    ).replace(queryParameters: queryParameters);
    return _request('GET', uri.toString(), authenticated: true);
  }

  Future<void> moderateReview({
    required String reviewId,
    required String status,
    required String reason,
  }) async {
    await _request(
      'PATCH',
      '/api/v1/admin/reviews/${Uri.encodeComponent(reviewId)}/moderation',
      authenticated: true,
      body: {'status': status, 'reason': reason},
    );
  }

  Future<List<Map<String, dynamic>>> loadAdminAuditEvents() async {
    final result = await _request(
      'GET',
      '/api/v1/admin/audit-events?limit=100',
      authenticated: true,
    );
    return (result['events'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((event) => event['entityType'] == 'Review')
        .toList(growable: false);
  }

  Future<List<ProblemReportItem>> _loadReports(String path) async {
    final result = await _request('GET', path, authenticated: true);
    return _parseReports(result);
  }

  List<ProblemReportItem> _parseReports(Map<String, dynamic> result) =>
      (result['reports'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ProblemReportItem.fromJson)
          .toList(growable: false);

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    bool authenticated = false,
    Map<String, Object?>? body,
    List<UploadFile> files = const [],
    String fileField = 'files',
  }) async {
    final token = tokenProvider();
    if (authenticated && (token == null || token.isEmpty)) {
      throw StateError('Sign in to continue.');
    }
    try {
      final uri = path.startsWith('http')
          ? Uri.parse(path)
          : EnvConfig.endpoint(path);
      final http.BaseRequest request;
      if (files.isEmpty) {
        final json = http.Request(method, uri)
          ..headers['content-type'] = 'application/json';
        if (body != null) json.body = jsonEncode(body);
        request = json;
      } else {
        final multipart = http.MultipartRequest(method, uri);
        body?.forEach((key, value) {
          if (value != null) multipart.fields[key] = '$value';
        });
        for (final file in files) {
          multipart.files.add(
            http.MultipartFile.fromBytes(
              fileField,
              file.bytes,
              filename: file.name,
            ),
          );
        }
        request = multipart;
      }
      if (token?.isNotEmpty ?? false) {
        request.headers['authorization'] = 'Bearer $token';
      }
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);
      if (response.statusCode >= 400) {
        final message = decoded is Map<String, dynamic>
            ? decoded['message'] as String? ?? decoded['error'] as String?
            : null;
        throw StateError(message ?? 'The request was rejected.');
      }
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('We could not reach Haven Link.');
    }
  }
}
