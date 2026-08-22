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

  test('adds app and authenticated runtime version context', () {
    final connection = Object();
    CrashReporting.configureAppVersion(version: '0.29.0', build: '104');
    CrashReporting.updateRuntimeContext(connection, <String, Object?>{
      'runtimeHostVersion': '1.7.0',
      'runtimeHostCommit': 'abc1234',
      'protocolVersion': 4,
    });
    CrashReporting.setEnabled(true);

    final event = CrashReporting.filterEvent(SentryEvent());

    expect(event!.tags, containsPair('surface', 'mobile'));
    expect(event.tags, containsPair('app_version', '0.29.0'));
    expect(event.tags, containsPair('app_build', '104'));
    expect(event.tags, containsPair('runtime_state', 'connected'));
    expect(event.tags, containsPair('runtime_version', '1.7.0'));
    expect(event.tags, containsPair('runtime_build', 'abc1234'));
    expect(event.tags, containsPair('runtime_protocol', '4'));
    expect(
      event.contexts['alera_versions'],
      containsPair('runtime_version', '1.7.0'),
    );
  });

  test('does not misattribute errors when connected host versions differ', () {
    CrashReporting.updateRuntimeContext(Object(), <String, Object?>{
      'runtimeHostVersion': '1.7.0',
      'runtimeHostCommit': 'aaa',
      'protocolVersion': 4,
    });
    CrashReporting.updateRuntimeContext(Object(), <String, Object?>{
      'runtimeHostVersion': '1.8.0',
      'runtimeHostCommit': 'bbb',
      'protocolVersion': 4,
    });
    CrashReporting.setEnabled(true);

    final event = CrashReporting.filterEvent(SentryEvent());

    expect(event!.tags, containsPair('runtime_state', 'multiple'));
    expect(event.tags, isNot(contains('runtime_version')));
    expect(
      (event.contexts['alera_versions']
          as Map<String, Object?>)['runtime_versions'],
      hasLength(2),
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
