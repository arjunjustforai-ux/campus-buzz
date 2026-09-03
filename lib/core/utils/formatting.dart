import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

/// Timestamps are stored in UTC; we render in the campus timezone.
abstract final class Fmt {
  static tz.Location location(String timeZone) {
    if (timeZone == 'UTC' || timeZone == 'Etc/UTC') return tz.UTC;
    try {
      return tz.getLocation(timeZone);
    } catch (_) {
      return tz.getLocation('Asia/Kolkata');
    }
  }

  static tz.TZDateTime inCampus(DateTime utc, String timeZone) => tz.TZDateTime.from(utc, location(timeZone));

  static String date(DateTime utc, String timeZone) => DateFormat('EEE, d MMM').format(inCampus(utc, timeZone));
  static String longDate(DateTime utc, String timeZone) => DateFormat('EEEE, d MMMM yyyy').format(inCampus(utc, timeZone));
  static String time(DateTime utc, String timeZone) => DateFormat('h:mm a').format(inCampus(utc, timeZone));
  static String dateTime(DateTime utc, String timeZone) => '${date(utc, timeZone)} · ${time(utc, timeZone)}';
  static String monthDay(DateTime utc, String timeZone) => DateFormat('d MMM').format(inCampus(utc, timeZone));
  static String dayLabel(DateTime utc, String timeZone, {DateTime? now}) {
    final local = inCampus(utc, timeZone);
    final today = inCampus(now ?? DateTime.now().toUtc(), timeZone);
    final d = DateTime(local.year, local.month, local.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (d == 0) return 'Today';
    if (d == 1) return 'Tomorrow';
    if (d == -1) return 'Yesterday';
    if (d > 1 && d < 7) return DateFormat('EEEE').format(local);
    return DateFormat('EEE, d MMM').format(local);
  }

  static String relative(DateTime utc, {DateTime? now}) {
    final diff = (now ?? DateTime.now().toUtc()).difference(utc);
    if (diff.inSeconds.abs() < 60) return 'just now';
    if (diff.inMinutes.abs() < 60) return diff.isNegative ? 'in ${-diff.inMinutes}m' : '${diff.inMinutes}m ago';
    if (diff.inHours.abs() < 24) return diff.isNegative ? 'in ${-diff.inHours}h' : '${diff.inHours}h ago';
    return diff.isNegative ? 'in ${-diff.inDays}d' : '${diff.inDays}d ago';
  }

  static String coins(num n) => NumberFormat.decimalPattern('en_IN').format(n);
  static String pct(num? n, {int digits = 0}) => n == null ? '—' : '${n.toStringAsFixed(digits)}%';
  static String rupees(num n) => NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);
  static String compact(num n) => NumberFormat.compact(locale: 'en_IN').format(n);

  static DateTime? toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate().toUtc();
    if (v is DateTime) return v.toUtc();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
    if (v is String) return DateTime.tryParse(v)?.toUtc();
    return null;
  }
}
