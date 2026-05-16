import 'package:intl/intl.dart';

/// Backend stores UTC; API returns timezone-aware ISO 8601; UI uses device local time.
class TimeUtils {
  TimeUtils._();

  /// Parse API ISO 8601 and return a local [DateTime] for display and pickers.
  static DateTime parseUtc(String value) {
    return DateTime.parse(value).toLocal();
  }

  static DateTime? tryParseUtc(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.parse(value.trim()).toLocal();
  }

  /// Serialize a local wall-clock instant for FastAPI (UTC ISO 8601).
  static String toUtcIso(DateTime local) => local.toUtc().toIso8601String();

  /// Format an API datetime string in the device timezone.
  static String formatLocalTime(
    String? utcString, {
    String pattern = 'MM-dd HH:mm',
  }) {
    final dt = tryParseUtc(utcString);
    if (dt == null) return '—';
    return DateFormat(pattern).format(dt);
  }

  /// Format an already-local [DateTime] (e.g. from DTOs that called [tryParseUtc]).
  static String formatLocalDateTime(
    DateTime local, {
    String pattern = 'MM-dd HH:mm',
  }) {
    return DateFormat(pattern).format(local);
  }
}
