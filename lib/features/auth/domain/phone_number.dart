/// Tanzanian mobile numbers, normalised to E.164.
///
/// Haven Link stores every phone number as `+255XXXXXXXXX` so verification
/// challenges, unlock records and call actions all address the same number.
class TanzanianPhone {
  const TanzanianPhone._();

  static const String countryCode = '255';
  static const String prefix = '+255';

  static final RegExp _separator = RegExp(r'[\s\-\(\)\.]');
  static final RegExp _plus = RegExp(r'^\+');

  /// Returns the E.164 form of [input], or `null` when it is not a valid
  /// Tanzanian mobile number.
  ///
  /// Accepted shapes:
  /// `+255 754 123 456`, `0754123456`, `0612345678`, `754123456`, `255754123456`.
  static String? tryNormalize(String input) {
    final cleaned = input.replaceAll(_separator, '').trim();
    if (cleaned.isEmpty) return null;

    final hasPlus = _plus.hasMatch(cleaned);
    var digits = cleaned.replaceAll(_plus, '');
    if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) return null;

    if (digits.startsWith(countryCode)) {
      digits = digits.substring(countryCode.length);
    } else if (digits.startsWith('0')) {
      digits = digits.substring(1);
    } else if (hasPlus) {
      // An international number that does not use the +255 country code.
      return null;
    }

    // The Tanzanian national significant number is 9 digits and mobile
    // numbers start with 6 or 7 (for example +255 754 123 456).
    if (digits.length != 9) return null;
    if (!RegExp(r'^[67]').hasMatch(digits)) return null;

    return '$prefix$digits';
  }

  static bool isValid(String input) => tryNormalize(input) != null;

  /// `+255754123456` -> `+255 754 123 456` for display.
  static String formatForDisplay(String e164) {
    final digits = e164.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 12 || !digits.startsWith(countryCode)) return e164;
    final national = digits.substring(countryCode.length);
    return '$prefix ${national.substring(0, 3)} ${national.substring(3, 6)} '
        '${national.substring(6)}';
  }

  /// `+255754123456` -> `+255 754 *** 456` so screens can confirm the
  /// destination without re-exposing the full number in logs or screenshots.
  static String mask(String e164) {
    final formatted = formatForDisplay(e164);
    if (formatted.length < 12) return formatted;
    final parts = formatted.split(' ');
    if (parts.length != 4) return formatted;
    return '${parts[0]} ${parts[1]} *** ${parts[3]}';
  }
}
