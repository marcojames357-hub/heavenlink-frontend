import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/env_config.dart';

class AdminUserRecord {
  const AdminUserRecord({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
    required this.verification,
    required this.enabled,
    required this.capabilities,
  });

  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String role;
  final String verification;
  final bool enabled;
  final Set<String> capabilities;

  factory AdminUserRecord.fromJson(Map<String, dynamic> json) =>
      AdminUserRecord(
        id: json['id'] as String,
        fullName: json['fullName'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        role: json['role'] as String? ?? 'CUSTOMER',
        verification: json['verification'] as String? ?? 'unverified',
        enabled: json['accountEnabled'] as bool? ?? true,
        capabilities: (json['capabilities'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet(),
      );
}

class AdminUsersRepository {
  AdminUsersRepository({required this._tokenProvider, http.Client? client})
    : _client = client ?? http.Client();

  final String? Function() _tokenProvider;
  final http.Client _client;

  Future<List<AdminUserRecord>> loadUsers() async {
    final response = await _send('GET', '/api/v1/admin/users');
    final root = jsonDecode(response.body) as Map<String, dynamic>;
    return (root['users'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AdminUserRecord.fromJson)
        .toList(growable: false);
  }

  Future<void> updateUser(
    AdminUserRecord user, {
    required String role,
    required Set<String> capabilities,
    required bool enabled,
  }) async {
    final response = await _send(
      'PUT',
      '/api/v1/admin/users/${Uri.encodeComponent(user.id)}',
      body: {
        'role': role,
        'capabilities': capabilities.toList(),
        'accountEnabled': enabled,
      },
    );
    if (response.statusCode >= 400) _throwError(response);
  }

  Future<Map<String, String>> loadWorkspaces(String userId) async {
    final response = await _send(
      'GET',
      '/api/v1/workspaces/admin/${Uri.encodeComponent(userId)}',
    );
    final root = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      for (final item
          in (root['workspaces'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>())
        item['workspace'] as String: item['status'] as String,
    };
  }

  Future<void> setWorkspaceStatus(
    String userId,
    String workspace,
    String status,
  ) async {
    await _send(
      'PATCH',
      '/api/v1/workspaces/admin/${Uri.encodeComponent(userId)}/$workspace',
      body: {'status': status},
    );
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final token = _tokenProvider();
    if (token == null || token.isEmpty) {
      throw StateError('Administrator sign-in is required.');
    }
    try {
      final request = http.Request(method, EnvConfig.endpoint(path))
        ..headers['authorization'] = 'Bearer $token'
        ..headers['content-type'] = 'application/json';
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 400) _throwError(response);
      return response;
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('We could not reach Haven Link administration.');
    }
  }

  Never _throwError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw StateError(
        body['message'] as String? ??
            body['error'] as String? ??
            'Admin request failed.',
      );
    } catch (error) {
      if (error is StateError) rethrow;
      throw StateError('Admin request failed.');
    }
  }
}
