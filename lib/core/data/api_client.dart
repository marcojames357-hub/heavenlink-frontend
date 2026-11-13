import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/env_config.dart';

/// Minimal authenticated JSON client for the Haven Link API.
///
/// Errors surface as [StateError] carrying the server's message so screens can
/// show them directly.
class ApiClient {
  ApiClient({required this.tokenProvider, http.Client? client})
    : _client = client ?? http.Client();

  final String? Function() tokenProvider;
  final http.Client _client;

  Future<Map<String, dynamic>> get(String path) => _send('GET', path);

  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, Object?>? body,
  ]) => _send('POST', path, body);

  Future<Map<String, dynamic>> put(String path, [Map<String, Object?>? body]) =>
      _send('PUT', path, body);

  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final token = tokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('Sign in again to continue.');
    }
    try {
      final request = http.Request(method, EnvConfig.endpoint(path))
        ..headers['authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['content-type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 20)),
      );
      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      final map = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      if (response.statusCode >= 400) {
        throw StateError(
          (map['error'] ?? map['message'] ?? 'The request was rejected.')
              .toString(),
        );
      }
      return map;
    } catch (error) {
      if (error is StateError) rethrow;
      throw StateError('We could not reach Haven Link. Check your connection.');
    }
  }
}
