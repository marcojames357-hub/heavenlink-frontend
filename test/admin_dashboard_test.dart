import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:haven_link/core/data/api_client.dart';
import 'package:haven_link/features/admin/data/admin_dashboard_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('admin overview parses live backend metrics', () async {
    final api = ApiClient(
      tokenProvider: () => 'admin-token',
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/admin/dashboard');
        expect(request.headers['authorization'], 'Bearer admin-token');
        return http.Response(
          jsonEncode({
            'stats': {
              'users': {'total': 24},
              'properties': {'total': 18},
              'bookings': {'total': 42},
              'transactions': {'totalRevenue': 1750000},
            },
          }),
          200,
        );
      }),
    );
    final repository = AdminDashboardRepository(
      tokenProvider: () => 'admin-token',
      api: api,
    );

    final summary = await repository.loadSummary();

    expect(summary.totalUsers, 24);
    expect(summary.totalProperties, 18);
    expect(summary.totalBookings, 42);
    expect(summary.totalRevenueTzs, 1750000);
  });

  test(
    'audit history maps actor details and limits the backend request',
    () async {
      final api = ApiClient(
        tokenProvider: () => 'admin-token',
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/admin/audit-events');
          expect(request.url.queryParameters['limit'], '100');
          return http.Response(
            jsonEncode({
              'events': [
                {
                  'id': 'audit-1',
                  'action': 'BUSINESS_FEES_UPDATED',
                  'entityType': 'BusinessConfiguration',
                  'entityId': 'main',
                  'actor': {'fullName': 'Platform Admin'},
                  'createdAt': '2026-11-11T12:30:00.000Z',
                  'metadata': {'bookingFeeRate': 0.03},
                },
              ],
            }),
            200,
          );
        }),
      );
      final repository = AdminDashboardRepository(
        tokenProvider: () => 'admin-token',
        api: api,
      );

      final events = await repository.loadAuditEvents();

      expect(events, hasLength(1));
      expect(events.single.action, 'BUSINESS_FEES_UPDATED');
      expect(events.single.actorName, 'Platform Admin');
      expect(events.single.metadata['bookingFeeRate'], 0.03);
    },
  );

  test('admin overview rejects an incomplete backend response', () async {
    final repository = AdminDashboardRepository(
      tokenProvider: () => 'admin-token',
      api: ApiClient(
        tokenProvider: () => 'admin-token',
        client: MockClient(
          (_) async => http.Response(jsonEncode({'stats': {}}), 200),
        ),
      ),
    );

    await expectLater(repository.loadSummary(), throwsStateError);
  });
}
