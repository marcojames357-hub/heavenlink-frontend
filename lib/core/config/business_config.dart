/// Static business defaults for Haven Link.
///
/// Runtime values live in `FeeSettings`; these constants are the seeds and the
/// validation bounds the admin portal must respect.
class BusinessConfig {
  const BusinessConfig._();

  /// Default Haven Link accommodation service fee (2%).
  static const double bookingFeeRate = 0.02;

  /// Maximum accommodation service fee an administrator may configure.
  static const double maxBookingFeeRate = 0.25;

  /// Default rental contact-unlock fee.
  static const int defaultUnlockFeeTzs = 5000;

  /// Validation bounds for the admin-configured unlock fee.
  static const int minUnlockFeeTzs = 500;
  static const int maxUnlockFeeTzs = 50000;

  static const String currencyCode = 'TZS';

  /// Listings require administrator approval before they go public.
  static const bool requiresListingApproval = true;
}
