import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/env_config.dart';

class CustomerDataRepository {
  CustomerDataRepository({required this._tokenProvider, http.Client? client})
    : _client = client ?? http.Client();

  final String? Function() _tokenProvider;
  final http.Client _client;

  Future<Map<String, dynamic>> createBooking({
    required String propertyId,
    required String idempotencyKey,
    required DateTime checkIn,
    required DateTime checkOut,
    required String guestName,
  }) => _request(
    'POST',
    '/api/v1/bookings',
    body: {
      'requestKey': idempotencyKey,
      'propertyId': propertyId,
      'checkIn': checkIn.toIso8601String(),
      'checkOut': checkOut.toIso8601String(),
      'guestName': guestName,
      'guestCount': 1,
    },
  );

  Future<void> cancelBooking(String bookingId) async {
    await _request('POST', '/api/v1/bookings/$bookingId/cancel');
  }

  Future<List<Map<String, dynamic>>> loadBookings() async =>
      _list(await _request('GET', '/api/v1/bookings'), 'bookings');

  Future<List<Map<String, dynamic>>> loadUnlocks() async =>
      _list(await _request('GET', '/api/v1/payments/unlocks'), 'unlocks');

  Future<List<Map<String, dynamic>>> loadPaymentHistory() async =>
      _list(await _request('GET', '/api/v1/payments/history'), 'transactions');

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? headers,
  }) async {
    final token = _tokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in to access your Haven Link account data.');
    }
    try {
      final request = http.Request(method, EnvConfig.endpoint(path))
        ..headers.addAll({
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
          ...?headers,
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
        throw StateError(message ?? 'Your account request was rejected.');
      }
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('We could not reach Haven Link account data.');
    }
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> result, String key) =>
      (result[key] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
}
