import 'package:alera/src/features/pull_requests/domain/comment_relative_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 12, 12);

  String? label(Duration age) =>
      commentRelativeTimeLabel(now.subtract(age), now);

  test('reads the first minute as just now', () {
    expect(label(Duration.zero), 'just now');
    expect(label(const Duration(seconds: 59)), 'just now');
  });

  test('reads future timestamps as just now', () {
    expect(
      commentRelativeTimeLabel(now.add(const Duration(hours: 2)), now),
      'just now',
    );
  });

  test('counts minutes, hours, and days at their boundaries', () {
    expect(label(const Duration(seconds: 60)), '1m ago');
    expect(label(const Duration(minutes: 59)), '59m ago');
    expect(label(const Duration(minutes: 60)), '1h ago');
    expect(label(const Duration(hours: 23, minutes: 59)), '23h ago');
    expect(label(const Duration(hours: 24)), '1d ago');
    expect(label(const Duration(days: 6, hours: 23)), '6d ago');
  });

  test('returns null from one week on so callers show a date', () {
    expect(label(const Duration(days: 7)), isNull);
    expect(label(const Duration(days: 400)), isNull);
  });

  test('compares instants regardless of time zone', () {
    final local = now.toLocal().subtract(const Duration(minutes: 5));
    expect(commentRelativeTimeLabel(local, now), '5m ago');
  });
}
