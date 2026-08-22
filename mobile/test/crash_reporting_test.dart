import 'dart:io';

import 'package:alera_mobile/src/features/diagnostics/infra/crash_reporting.dart';
import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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

  test('drops typed host reachability events', () {
    CrashReporting.setEnabled(true);
    final failure = HostUnreachableException(
      SocketException(
        'No route to host',
        osError: const OSError('No route to host', 113),
      ),
    );

    expect(CrashReporting.filterEvent(SentryEvent(throwable: failure)), isNull);
    expect(
      CrashReporting.filterEvent(
        SentryEvent(
          exceptions: <SentryException>[
            SentryException(
              type: 'HostUnreachableException',
              value: failure.toString(),
              throwable: failure,
            ),
          ],
        ),
      ),
      isNull,
    );
  });

  test('keeps unclassified transport and programming errors reportable', () {
    CrashReporting.setEnabled(true);
    final rawTransport = WebSocketChannelException(
      'SocketException: No route to host (errno = 113)',
    );
    final tlsError = WebSocketChannelException.from(
      const HandshakeException('Certificate verification failed.'),
    );
    final programmingError = StateError('Unexpected response state.');

    for (final error in <Object>[rawTransport, tlsError, programmingError]) {
      final event = SentryEvent(throwable: error);
      expect(CrashReporting.filterEvent(event), same(event));
    }
  });
}
