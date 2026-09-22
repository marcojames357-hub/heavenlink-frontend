import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/env_config.dart';

class BusinessConfiguration {
  const BusinessConfiguration({
    required this.unlockFeeTzs,
    required this.bookingFeeRate,
    this.paymentMethods = const {},
  });

  final int unlockFeeTzs;
  final double bookingFeeRate;
  final Set<String> paymentMethods;
}

class BusinessConfigurationRepository {
  BusinessConfigurationRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<BusinessConfiguration> load() async {
    final response = await _client
        .get(EnvConfig.endpoint('/api/v1/payments/config'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode >= 400) {
      throw StateError('Business fees could not be loaded.');
    }
    final root = jsonDecode(response.body) as Map<String, dynamic>;
    final config = root['config'] as Map<String, dynamic>;
    return BusinessConfiguration(
      unlockFeeTzs: (config['unlockFeeTzs'] as num).toInt(),
      bookingFeeRate: (config['bookingFeeRate'] as num).toDouble(),
      paymentMethods: (config['paymentMethods'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((item) => item['id'] as String)
          .toSet(),
    );
  }

  Future<void> save({
    required String accessToken,
    required int unlockFeeTzs,
    required double bookingFeeRate,
  }) async {
    final response = await _client
        .put(
          EnvConfig.endpoint('/api/v1/admin/config'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({
            'unlockFeeTzs': unlockFeeTzs,
            'bookingFeeRate': bookingFeeRate,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode >= 400) {
      throw StateError('The server could not save the business fees.');
    }
  }
}
