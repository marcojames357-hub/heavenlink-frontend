import 'package:flutter/foundation.dart';

import '../config/business_config.dart';

/// Platform fees that administrators can change at runtime.
///
/// The static defaults in [BusinessConfig] seed this object; the admin portal
/// updates it and every customer-facing price reads from here, so a fee change
/// is immediately visible in listings, checkout and transaction history.
class FeeSettings extends ChangeNotifier {
  FeeSettings({int? unlockFeeTzs, double? bookingFeeRate})
    : _unlockFeeTzs = unlockFeeTzs ?? BusinessConfig.defaultUnlockFeeTzs,
      _bookingFeeRate = bookingFeeRate ?? BusinessConfig.bookingFeeRate;

  int _unlockFeeTzs;
  double _bookingFeeRate;

  /// Amount charged to reveal a rental owner/agent contact.
  int get unlockFeeTzs => _unlockFeeTzs;

  /// Haven Link service fee applied to short-stay accommodation bookings.
  double get bookingFeeRate => _bookingFeeRate;

  String get currencyCode => BusinessConfig.currencyCode;

  int bookingFeeFor(int subtotalTzs) =>
      (subtotalTzs * _bookingFeeRate).round().clamp(0, 1 << 31);

  /// Returns the validated new value, or throws [ArgumentError].
  void updateUnlockFee(int valueTzs) {
    if (valueTzs < BusinessConfig.minUnlockFeeTzs ||
        valueTzs > BusinessConfig.maxUnlockFeeTzs) {
      throw ArgumentError.value(
        valueTzs,
        'valueTzs',
        'Unlock fee must be between '
            '${BusinessConfig.minUnlockFeeTzs} and '
            '${BusinessConfig.maxUnlockFeeTzs} TZS.',
      );
    }
    if (valueTzs == _unlockFeeTzs) return;
    _unlockFeeTzs = valueTzs;
    notifyListeners();
  }

  /// Returns the validated new rate, or throws [ArgumentError].
  void updateBookingFeeRate(double rate) {
    if (rate < 0 || rate > BusinessConfig.maxBookingFeeRate) {
      throw ArgumentError.value(
        rate,
        'rate',
        'Service fee must be between 0 and '
            '${(BusinessConfig.maxBookingFeeRate * 100).toStringAsFixed(0)}%.',
      );
    }
    if (rate == _bookingFeeRate) return;
    _bookingFeeRate = rate;
    notifyListeners();
  }
}
