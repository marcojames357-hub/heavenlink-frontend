import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/env_config.dart';

class FinancialManagementRepository {
  FinancialManagementRepository({
    required this.tokenProvider,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String? Function() tokenProvider;
  final http.Client _client;

  Future<Map<String, dynamic>> loadDashboard({
    required String businessModel,
    String? propertyId,
    required DateTime from,
    required DateTime to,
  }) async {
    final uri = EnvConfig.endpoint('/api/v1/finance/dashboard').replace(
      queryParameters: {
        'businessModel': businessModel,
        ...?(propertyId == null ? null : {'propertyId': propertyId}),
        'from': _dateOnly(from),
        'to': _dateOnly(to),
      },
    );
    return _request('GET', uri.toString());
  }

  Future<Map<String, dynamic>> loadAdminOverview() =>
      _request('GET', '/api/v1/finance/admin/overview');

  Future<Map<String, dynamic>> loadAlerts({bool unread = false}) {
    final uri = EnvConfig.endpoint(
      '/api/v1/finance/alerts',
    ).replace(queryParameters: {'unread': '$unread'});
    return _request('GET', uri.toString());
  }

  Future<void> markAlertRead(String alertId) async {
    await _request(
      'PATCH',
      '/api/v1/finance/alerts/${Uri.encodeComponent(alertId)}/read',
    );
  }

  Future<Map<String, dynamic>> createRentObligation({
    required String propertyId,
    required Map<String, Object?> values,
  }) => _request(
    'POST',
    '/api/v1/finance/properties/${Uri.encodeComponent(propertyId)}/rent',
    body: values,
  );

  Future<Map<String, dynamic>> recordRentPayment({
    required String propertyId,
    required String obligationId,
    required Map<String, Object?> values,
  }) => _request(
    'POST',
    '/api/v1/finance/properties/${Uri.encodeComponent(propertyId)}'
        '/rent/${Uri.encodeComponent(obligationId)}/receipts',
    body: values,
  );

  Future<Map<String, dynamic>> updateRentTenancy({
    required String propertyId,
    required String obligationId,
    required Map<String, Object?> values,
  }) => _request(
    'PUT',
    '/api/v1/finance/properties/${Uri.encodeComponent(propertyId)}'
        '/rent/${Uri.encodeComponent(obligationId)}/tenancy',
    body: values,
  );

  Future<Map<String, dynamic>> createExpense({
    required String propertyId,
    required Map<String, Object?> values,
  }) => _request(
    'POST',
    '/api/v1/finance/properties/${Uri.encodeComponent(propertyId)}/expenses',
    body: values,
  );

  Future<Map<String, dynamic>> createBill({
    required String propertyId,
    required Map<String, Object?> values,
  }) => _request(
    'POST',
    '/api/v1/finance/properties/${Uri.encodeComponent(propertyId)}/bills',
    body: values,
  );

  Future<Map<String, dynamic>> createStaffObligation({
    required String propertyId,
    required Map<String, Object?> values,
  }) => _request(
    'POST',
    '/api/v1/finance/properties/${Uri.encodeComponent(propertyId)}/staff',
    body: values,
  );

  Future<Map<String, dynamic>> recordPayment({
    required String propertyId,
    required String type,
    required String recordId,
    required Map<String, Object?> values,
  }) => _request(
    'POST',
    '/api/v1/finance/properties/${Uri.encodeComponent(propertyId)}'
        '/${Uri.encodeComponent(type)}/${Uri.encodeComponent(recordId)}/payments',
    body: values,
  );

  Future<Map<String, dynamic>> reversePayment({
    required String propertyId,
    required String paymentId,
    required String reason,
  }) => _request(
    'POST',
    '/api/v1/finance/properties/${Uri.encodeComponent(propertyId)}'
        '/payments/${Uri.encodeComponent(paymentId)}/reverse',
    body: {'reason': reason},
  );

  Future<Map<String, dynamic>> reverseRecord({
    required String propertyId,
    required String type,
    required String recordId,
    required String reason,
  }) => _request(
    'POST',
    '/api/v1/finance/properties/${Uri.encodeComponent(propertyId)}'
        '/${Uri.encodeComponent(type)}/${Uri.encodeComponent(recordId)}/reverse',
    body: {'reason': reason},
  );

  Future<Map<String, dynamic>> reverseExpense({
    required String propertyId,
    required String recordId,
    required String reason,
  }) => _request(
    'POST',
    '/api/v1/finance/properties/${Uri.encodeComponent(propertyId)}'
        '/expenses/${Uri.encodeComponent(recordId)}/reverse',
    body: {'reason': reason},
  );

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final token = tokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in to access financial management.');
    }
    final uri = path.startsWith('http')
        ? Uri.parse(path)
        : EnvConfig.endpoint(path);
    final headers = <String, String>{
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
    };
    final response = switch (method) {
      'GET' =>
        await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 30)),
      'POST' =>
        await _client
            .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(const Duration(seconds: 30)),
      'PATCH' =>
        await _client
            .patch(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(const Duration(seconds: 30)),
      'PUT' =>
        await _client
            .put(uri, headers: headers, body: jsonEncode(body ?? const {}))
            .timeout(const Duration(seconds: 30)),
      _ => throw ArgumentError.value(method, 'method'),
    };
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error'] as String? ?? decoded['message'] as String?
          : null;
      throw StateError(message ?? 'The request was rejected.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw StateError('The financial service returned an invalid response.');
    }
    return decoded;
  }

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
