import 'package:alera_mobile/src/features/diagnostics/infra/crash_reporting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  tearDown(CrashReporting.resetForTesting);

  test('drops events while crash reporting is disabled', () {
    final event = SentryEvent(message: SentryMessage('boom'));

    expect(CrashReporting.filterEvent(event), isNull);
  });

  test('redacts text-bearing event fields before sending', () {
    CrashReporting.setEnabled(true);
    final event = SentryEvent(
      message: SentryMessage('token=abcdef123456'),
      exceptions: <SentryException>[
        SentryException(type: 'StateError', value: 'token=abcdef123456'),
      ],
      breadcrumbs: <Breadcrumb>[Breadcrumb(message: 'token=abcdef123456')],
    );

    final filtered = CrashReporting.filterEvent(event);

    expect(filtered, same(event));
    expect(filtered!.message!.formatted, isNot(contains('abcdef123456')));
    expect(filtered.exceptions!.single.value, isNot(contains('abcdef123456')));
    expect(
      filtered.breadcrumbs!.single.message,
      isNot(contains('abcdef123456')),
    );
  });
}
