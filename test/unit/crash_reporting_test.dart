import 'dart:async';

import 'package:alera/src/features/diagnostics/infra/crash_reporting.dart';
import 'package:alera/src/shared/infra/logging/log_redaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry/sentry.dart';

void main() {
  setUp(() {
    CrashReporting.resetForTesting();
    resetRegisteredLogSecrets();
  });

  tearDown(() {
    CrashReporting.resetForTesting();
    resetRegisteredLogSecrets();
  });

  test('reporting is disabled by default', () {
    expect(CrashReporting.isEnabled, isFalse);
  });

  test('drops every event while reporting is off', () {
    final event = SentryEvent(message: SentryMessage('boom'));

    expect(CrashReporting.filterEvent(event), isNull);
  });

  test('keeps events once reporting is enabled', () {
    CrashReporting.setEnabled(true);
    final event = SentryEvent(message: SentryMessage('boom'));

    expect(CrashReporting.filterEvent(event), isNotNull);
  });

  test('redacts the message before it leaves the machine', () {
    CrashReporting.setEnabled(true);
    final event = SentryEvent(
      message: SentryMessage('attach failed with token=abcdef123456'),
    );

    final filtered = CrashReporting.filterEvent(event);

    expect(filtered!.message!.formatted, isNot(contains('abcdef123456')));
    expect(filtered.message!.formatted, contains(kRedactedPlaceholder));
  });

  test('redacts a registered literal inside an exception value', () {
    CrashReporting.setEnabled(true);
    registerLogSecret('sentry-runtime-token-xyz');
    final event = SentryEvent(
      exceptions: <SentryException>[
        SentryException(
          type: 'StateError',
          value: 'host rejected sentry-runtime-token-xyz',
          throwable: null,
        ),
      ],
    );

    final filtered = CrashReporting.filterEvent(event);

    expect(
      filtered!.exceptions!.single.value,
      isNot(contains('sentry-runtime-token-xyz')),
    );
  });

  test('redacts breadcrumb messages', () {
    CrashReporting.setEnabled(true);
    final event = SentryEvent(
      breadcrumbs: <Breadcrumb>[
        Breadcrumb(message: 'sent Bearer eyJhbGciOiJIUzI1NiJ9.payload'),
      ],
    );

    final filtered = CrashReporting.filterEvent(event);

    expect(
      filtered!.breadcrumbs!.single.message,
      isNot(contains('eyJhbGciOiJIUzI1NiJ9.payload')),
    );
  });

  test('turning reporting back off stops events immediately', () {
    CrashReporting.setEnabled(true);
    expect(
      CrashReporting.filterEvent(SentryEvent(message: SentryMessage('a'))),
      isNotNull,
    );

    CrashReporting.setEnabled(false);

    expect(
      CrashReporting.filterEvent(SentryEvent(message: SentryMessage('b'))),
      isNull,
    );
  });

  test('runs the app callback in the caller zone', () async {
    final callerZone = Zone.current;
    late Zone appZone;

    try {
      await CrashReporting.run(
        enabled: false,
        release: 'alera@test',
        appRunner: () => appZone = Zone.current,
      );
    } finally {
      await Sentry.close();
    }

    expect(appZone, same(callerZone));
  });
}
