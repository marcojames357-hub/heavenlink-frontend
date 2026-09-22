/// Lifecycle of a rental contact unlock.
enum UnlockStatus {
  /// Payment created but not yet confirmed by the provider.
  awaitingPayment,

  /// Provider confirmed the payment — access is granted.
  active,

  /// Provider reported a failure, cancellation or expiry.
  failed,

  /// Money returned to the customer; access withdrawn.
  refunded,
}

/// A granted rental contact unlock.
///
/// Rows are unique on `(customerId, listingId)`: one customer pays for one
/// listing once, and that access survives sign-out because it is keyed to the
/// account rather than to a device or a session.
class UnlockRecord {
  const UnlockRecord({
    required this.id,
    required this.customerId,
    required this.listingId,
    required this.paymentTransactionId,
    required this.status,
    required this.createdAt,
    this.confirmedAt,
    this.amountTzs,
  });

  final String id;
  final String customerId;
  final String listingId;
  final String paymentTransactionId;
  final UnlockStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final int? amountTzs;

  bool get isActive => status == UnlockStatus.active;

  UnlockRecord copyWith({UnlockStatus? status, DateTime? confirmedAt}) {
    return UnlockRecord(
      id: id,
      customerId: customerId,
      listingId: listingId,
      paymentTransactionId: paymentTransactionId,
      status: status ?? this.status,
      createdAt: createdAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      amountTzs: amountTzs,
    );
  }

  Map<String, Object?> toAuditJson() => {
    'unlockId': id,
    'customerId': customerId,
    'listingId': listingId,
    'paymentTransactionId': paymentTransactionId,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    if (confirmedAt != null) 'confirmedAt': confirmedAt!.toIso8601String(),
  };
}

/// Raised when a protected contact is requested without an active unlock.
class ContactNotUnlockedException implements Exception {
  const ContactNotUnlockedException([
    this.message =
        'This listing is still locked. A confirmed payment is required first.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Raised when payment verification did not succeed.
class PaymentNotVerifiedException implements Exception {
  const PaymentNotVerifiedException([
    this.message =
        'Payment has not been confirmed yet, so the contact stays locked.',
  ]);

  final String message;

  @override
  String toString() => message;
}
