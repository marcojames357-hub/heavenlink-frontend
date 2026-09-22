import 'package:intl/intl.dart';

final NumberFormat _tzsFormat = NumberFormat.currency(
  locale: 'en_TZ',
  name: 'TZS',
  symbol: 'TZS ',
  decimalDigits: 0,
);

String formatTzs(num amount) => _tzsFormat.format(amount);
