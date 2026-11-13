import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/env_config.dart';
import '../../../core/config/business_config.dart';

/// Why money is being taken.
///
/// Rental contact unlocks and accommodation bookings are deliberately kept as
/// separate transaction types: an unlock payment can never confirm a booking,
/// and a booking payment can never release a protected contact.
enum PaymentPurpose {
  rentalContactUnlock('Rental contact unlock'),
  accommodationBooking('Accommodation booking');

  const PaymentPurpose(this.label);

  final String label;
}

enum PaymentTransactionStatus {
  pending('Pending'),
  succeeded('Successful'),
  failed('Failed'),
  cancelled('Cancelled'),
  expired('Expired'),
  refunded('Refunded');

  const PaymentTransactionStatus(this.label);

  final String label;

  /// The only status that may release protected data.
  bool get isVerified => this == PaymentTransactionStatus.succeeded;
}

/// A payment rail offered to customers.
///
/// A method is only ever listed once its integration has been configured, so
/// nothing is presented as active before it works.
class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.label,
    required this.isPreview,
  });

  final String id;
  final String label;

  /// Development stand-in that moves no money.
  final bool isPreview;
}

const PaymentMethod kMpesa = PaymentMethod(
  id: 'mpesa',
  label: 'M-Pesa',
  isPreview: false,
);
const PaymentMethod kAirtelMoney = PaymentMethod(
  id: 'airtel',
  label: 'Airtel Money',
  isPreview: false,
);
const PaymentMethod kTigoPesa = PaymentMethod(
  id: 'tigopesa',
  label: 'Tigo Pesa',
  isPreview: false,
);
const PaymentMethod kCard = PaymentMethod(
  id: 'card',
  label: 'Visa / Mastercard',
  isPreview: false,
);
const PaymentMethod kPreviewMethod = PaymentMethod(
  id: 'preview',
  label: 'Preview payment (no money moves)',
  isPreview: true,
);

const List<PaymentMethod> kConfigurableMethods = [
  kMpesa,
  kAirtelMoney,
  kTigoPesa,
  kCard,
];

/// Methods that may be offered in this build.
List<PaymentMethod> availablePaymentMethods() {
  final enabled = EnvConfig.enabledPaymentMethodIds;
  final configured = kConfigurableMethods
      .where((method) => enabled.contains(method.id))
      .toList(growable: false);
  if (configured.isNotEmpty) return configured;
  if (EnvConfig.previewPaymentsEnabled) return const [kPreviewMethod];
  return const [];
}

/// A payment as the backend reports it.
///
/// [status] is filled from a trusted provider response or a server-to-server
/// verification — never from anything the client claims.
class PaymentTransaction {
  const PaymentTransaction({
    required this.id,
    required this.reference,
    required this.purpose,
    required this.amountTzs,
    required this.currency,
    required this.methodId,
    required this.customerId,
    required this.status,
    required this.createdAt,
    this.listingId,
    this.bookingId,
    this.verifiedAt,
    this.failureMessage,
  });

  final String id;
  final String reference;
  final PaymentPurpose purpose;
  final int amountTzs;
  final String currency;
  final String methodId;
  final String customerId;

  /// Set for rental unlocks so an unlock can only ever apply to its own listing.
  final String? listingId;
  final String? bookingId;

  final PaymentTransactionStatus status;
  final DateTime createdAt;
  final DateTime? verifiedAt;
  final String? failureMessage;

  bool get isVerified => status.isVerified;

  PaymentTransaction copyWith({
    PaymentTransactionStatus? status,
    DateTime? verifiedAt,
    String? failureMessage,
  }) {
    return PaymentTransaction(
      id: id,
      reference: reference,
      purpose: purpose,
      amountTzs: amountTzs,
      currency: currency,
      methodId: methodId,
      customerId: customerId,
      listingId: listingId,
      bookingId: bookingId,
      status: status ?? this.status,
      createdAt: createdAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      failureMessage: failureMessage ?? this.failureMessage,
    );
  }
}

class PaymentNotConfiguredException implements Exception {
  const PaymentNotConfiguredException([
    this.message =
        'No payment provider is configured for this build. Configure '
        'HAVEN_PAYMENT_METHODS before offering payments to customers.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class PaymentFailedException implements Exception {
  const PaymentFailedException([
    this.message = 'The payment could not be completed.',
  ]);

  final String message;

  @override
  String toString() => message;
}

class PaymentNetworkException implements Exception {
  const PaymentNetworkException([
    this.message =
        'We could not reach the payment service. Nothing was charged.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Payment access every checkout depends on.
///
/// The client never decides that a payment succeeded: it asks the service,
/// which in production asks the backend, which asks the provider.
abstract interface class PaymentService {
  String get providerLabel;

  bool get isConfigured;

  /// Opens a transaction. [idempotencyKey] makes retried requests return the
  /// same transaction instead of charging twice.
  Future<PaymentTransaction> createTransaction({
    required PaymentPurpose purpose,
    required int amountTzs,
    required String methodId,
    required String customerId,
    required String idempotencyKey,
    String? listingId,
    String? bookingId,
  });

  /// Authoritative status lookup — the only input trusted for granting access.
  Future<PaymentTransaction> fetchStatus(String transactionId);
}

/// Talks to the Haven Link backend, which owns every provider credential.
///
/// Status always comes back from the server, which performs server-to-server
/// verification with the mobile-money or card provider.
class HttpPaymentService implements PaymentService {
  HttpPaymentService({required this._tokenProvider, http.Client? client})
    : _client = client ?? http.Client();

  final String? Function() _tokenProvider;
  final http.Client _client;

  @override
  String get providerLabel => 'Haven Link payments';

  @override
  bool get isConfigured => EnvConfig.backendConfigured;

  @override
  Future<PaymentTransaction> createTransaction({
    required PaymentPurpose purpose,
    required int amountTzs,
    required String methodId,
    required String customerId,
    required String idempotencyKey,
    String? listingId,
    String? bookingId,
  }) async {
    final response = await _request(
      'POST',
      '/api/v1/payments/transactions',
      headers: {'idempotency-key': idempotencyKey},
      body: _buildRequestBody(
        purpose: purpose,
        amountTzs: amountTzs,
        methodId: methodId,
        listingId: listingId,
        bookingId: bookingId,
      ),
    );
    if (response.statusCode == 402) throw const PaymentFailedException();
    if (response.statusCode >= 400) throw const PaymentNetworkException();
    return _fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<PaymentTransaction> fetchStatus(String transactionId) async {
    final response = await _request(
      'POST',
      '/api/v1/payments/transactions/$transactionId/verify',
    );
    if (response.statusCode == 404) {
      throw const PaymentFailedException('Transaction not found.');
    }
    if (response.statusCode >= 400) throw const PaymentNetworkException();
    return _fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Map<String, Object?> _buildRequestBody({
    required PaymentPurpose purpose,
    required int amountTzs,
    required String methodId,
    String? listingId,
    String? bookingId,
  }) {
    final body = <String, Object?>{
      'purpose': purpose.name,
      'amountTzs': amountTzs,
      'currency': BusinessConfig.currencyCode,
      'methodId': methodId,
    };
    if (listingId != null) body['listingId'] = listingId;
    if (bookingId != null) body['bookingId'] = bookingId;
    return body;
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Map<String, String>? headers,
    Map<String, Object?>? body,
  }) async {
    try {
      final uri = EnvConfig.endpoint(path);
      final request = http.Request(method, uri)
        ..followRedirects = method != 'POST';
      request.headers.addAll({'content-type': 'application/json', ...?headers});
      final token = _tokenProvider();
      if (token?.isNotEmpty ?? false) {
        request.headers['authorization'] = 'Bearer $token';
      }
      request.body = jsonEncode(body ?? const {});
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 25));
      return await http.Response.fromStream(streamed);
    } catch (_) {
      throw const PaymentNetworkException();
    }
  }

  PaymentTransaction _fromJson(Map<String, dynamic> json) {
    final transaction = json['transaction'] is Map<String, dynamic>
        ? json['transaction'] as Map<String, dynamic>
        : json;
    return PaymentTransaction(
      id: transaction['id'] as String,
      reference: transaction['reference'] as String? ?? '',
      purpose: PaymentPurpose.values.firstWhere(
        (value) => value.name == transaction['purpose'],
        orElse: () => PaymentPurpose.rentalContactUnlock,
      ),
      amountTzs: (transaction['amountTzs'] as num).toInt(),
      currency:
          transaction['currency'] as String? ?? BusinessConfig.currencyCode,
      methodId:
          transaction['methodId'] as String? ??
          transaction['method'] as String? ??
          '',
      customerId: transaction['customerId'] as String? ?? '',
      listingId: transaction['listingId'] as String?,
      bookingId: transaction['bookingId'] as String?,
      status: PaymentTransactionStatus.values.firstWhere(
        (value) => value.name == transaction['status'],
        orElse: () => PaymentTransactionStatus.pending,
      ),
      createdAt:
          DateTime.tryParse(transaction['createdAt'] as String? ?? '') ??
          DateTime.now(),
      verifiedAt: DateTime.tryParse(transaction['verifiedAt'] as String? ?? ''),
    );
  }
}

/// Development stand-in that simulates the provider callback.
///
/// It never moves money and is only constructible in debug builds. The
/// transaction still starts as `pending` and only becomes `succeeded` after a
/// separate [fetchStatus] call, so the unlock path always exercises real
/// verification logic.
class PreviewPaymentService implements PaymentService {
  PreviewPaymentService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    assert(
      kDebugMode,
      'PreviewPaymentService must never run outside debug builds.',
    );
  }

  final DateTime Function() _clock;
  final Map<String, PaymentTransaction> _transactions = {};
  final Map<String, String> _seenIdempotencyKeys = {};
  int _sequence = 0;

  @override
  String get providerLabel => 'Local preview (no money moves)';

  @override
  bool get isConfigured => kDebugMode;

  @override
  Future<PaymentTransaction> createTransaction({
    required PaymentPurpose purpose,
    required int amountTzs,
    required String methodId,
    required String customerId,
    required String idempotencyKey,
    String? listingId,
    String? bookingId,
  }) async {
    if (amountTzs <= 0) {
      throw const PaymentFailedException('Enter a valid amount.');
    }
    // Replaying the same idempotency key returns the first transaction so a
    // retried request can never create a second charge.
    final existingId = _seenIdempotencyKeys[idempotencyKey];
    if (existingId != null) return _transactions[existingId]!;

    final now = _clock();
    _sequence += 1;
    final transaction = PaymentTransaction(
      id: 'txn_${now.microsecondsSinceEpoch}_$_sequence',
      reference: 'DEMO-${now.microsecondsSinceEpoch}',
      purpose: purpose,
      amountTzs: amountTzs,
      currency: BusinessConfig.currencyCode,
      methodId: methodId,
      customerId: customerId,
      listingId: listingId,
      bookingId: bookingId,
      status: PaymentTransactionStatus.pending,
      createdAt: now,
    );
    _transactions[transaction.id] = transaction;
    _seenIdempotencyKeys[idempotencyKey] = transaction.id;
    return transaction;
  }

  @override
  Future<PaymentTransaction> fetchStatus(String transactionId) async {
    final stored = _transactions[transactionId];
    if (stored == null) {
      throw const PaymentFailedException('Transaction not found.');
    }
    if (stored.status == PaymentTransactionStatus.pending) {
      // Simulates the provider callback having been confirmed server-side.
      final verified = stored.copyWith(
        status: PaymentTransactionStatus.succeeded,
        verifiedAt: _clock(),
      );
      _transactions[transactionId] = verified;
      return verified;
    }
    return stored;
  }
}

/// Returned when no payment provider and no backend are available.
class UnconfiguredPaymentService implements PaymentService {
  const UnconfiguredPaymentService();

  @override
  String get providerLabel => 'Not configured';

  @override
  bool get isConfigured => false;

  @override
  Future<PaymentTransaction> createTransaction({
    required PaymentPurpose purpose,
    required int amountTzs,
    required String methodId,
    required String customerId,
    required String idempotencyKey,
    String? listingId,
    String? bookingId,
  }) async => throw const PaymentNotConfiguredException();

  @override
  Future<PaymentTransaction> fetchStatus(String transactionId) async =>
      throw const PaymentNotConfiguredException();
}

/// Chooses the payment implementation for the current build configuration.
PaymentService resolvePaymentService({
  http.Client? client,
  required String? Function() tokenProvider,
}) {
  if (EnvConfig.backendConfigured) {
    return HttpPaymentService(client: client, tokenProvider: tokenProvider);
  }
  if (EnvConfig.previewPaymentsEnabled) return PreviewPaymentService();
  return const UnconfiguredPaymentService();
}
