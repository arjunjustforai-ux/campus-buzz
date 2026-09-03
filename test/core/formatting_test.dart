import 'package:campusbuzz/core/utils/formatting.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('renders UTC timestamps in the campus timezone', () {
    final utc = DateTime.utc(2026, 9, 6, 18, 30); // 00:00 IST next day
    expect(Fmt.inCampus(utc, 'Asia/Kolkata').hour, 0);
    expect(Fmt.inCampus(utc, 'Asia/Kolkata').day, 7);
    expect(Fmt.time(utc, 'Asia/Kolkata'), contains('12:00'));
    expect(Fmt.date(utc, 'Asia/Kolkata'), contains('7 Sep'));
    expect(Fmt.date(utc, 'UTC'), contains('6 Sep'));
  });

  test('day labels are relative to campus-local today', () {
    final now = DateTime.utc(2026, 9, 6, 18, 30); // Mon 00:00 IST
    expect(Fmt.dayLabel(now, 'Asia/Kolkata', now: now), 'Today');
    expect(Fmt.dayLabel(now.add(const Duration(hours: 20)), 'Asia/Kolkata', now: now), 'Today');
    expect(Fmt.dayLabel(now.add(const Duration(days: 1)), 'Asia/Kolkata', now: now), 'Tomorrow');
    expect(Fmt.dayLabel(now.add(const Duration(days: 3)), 'Asia/Kolkata', now: now), 'Thursday');
  });

  test('coins, percentages and rupees', () {
    expect(Fmt.coins(12345), '12,345');
    expect(Fmt.pct(33.333, digits: 1), '33.3%');
    expect(Fmt.pct(null), '—');
    expect(Fmt.rupees(1299), '₹1,299');
  });

  test('toDate accepts Timestamp, DateTime, int, ISO string', () {
    final d = DateTime.utc(2026, 1, 1);
    expect(Fmt.toDate(Timestamp.fromDate(d)), d);
    expect(Fmt.toDate(d.millisecondsSinceEpoch), d);
    expect(Fmt.toDate(d.toIso8601String()), d);
    expect(Fmt.toDate(null), isNull);
    expect(Fmt.toDate('nope'), isNull);
  });

  test('unknown timezone falls back safely', () {
    expect(() => Fmt.time(DateTime.now().toUtc(), 'Not/AZone'), returnsNormally);
  });
}
