import 'dart:async';

import 'package:alera_mobile/src/core/errors/action_failure_feedback.dart';
import 'package:alera_mobile/src/core/errors/user_facing_error_message.dart';
import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_action_error_message.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

class _Opaque {}

void main() {
  group('userFacingErrorMessage', () {
    test('drops the Bad state prefix from StateError', () {
      expect(
        '${StateError('Nothing to commit.')}',
        'Bad state: Nothing to commit.',
      );
      expect(
        userFacingErrorMessage(StateError('Nothing to commit.')),
        'Nothing to commit.',
      );
    });

    test('shows the runtime text of a RuntimeRequestError', () {
      final error = RuntimeRequestError(
        'workspace is busy',
        code: 'sourceControlBusy',
      );
      expect('$error', 'workspace is busy');
      expect(userFacingErrorMessage(error), 'Workspace is busy');
      expect(error, isA<StateError>());
    });

    test('strips nested type prefixes', () {
      expect(
        userFacingErrorMessage(
          Exception('Bad state: FormatException: unexpected end of input'),
        ),
        'Unexpected end of input',
      );
      expect(
        userFacingErrorMessage(
          'RelayCryptoException: Invalid argument(s): key too short',
        ),
        'Key too short',
      );
      expect(
        userFacingErrorMessage(const FormatException('bad offer')),
        'Bad offer',
      );
      expect(
        userFacingErrorMessage(ArgumentError('port out of range')),
        'Port out of range',
      );
    });

    test('keeps identifiers and paths as written', () {
      expect(
        userFacingErrorMessage(StateError('npm not found')),
        'npm not found',
      );
      expect(
        userFacingErrorMessage(StateError('./setup.sh exited 1')),
        './setup.sh exited 1',
      );
    });

    test('never returns an empty message', () {
      expect(userFacingErrorMessage(null), unknownErrorMessage);
      expect(userFacingErrorMessage(Exception('')), unknownErrorMessage);
      expect(userFacingErrorMessage(StateError('  ')), unknownErrorMessage);
      expect(userFacingErrorMessage(_Opaque()), unknownErrorMessage);
      expect(
        userFacingErrorMessage(_Opaque(), fallback: 'Try again.'),
        'Try again.',
      );
    });

    test('keeps custom exception text', () {
      expect(
        userFacingErrorMessage(const HostUnreachableException()),
        'Could not reach the host',
      );
      expect(
        userFacingErrorMessage(TimeoutException('Speech provider timed out.')),
        'Speech provider timed out.',
      );
    });
  });

  group('actionFailureMessage', () {
    test('names the action and its cause', () {
      expect(
        actionFailureMessage('rename tab', StateError('tab not found')),
        'Could not rename tab: Tab not found',
      );
    });

    test('falls back to the logs when the cause is unreadable', () {
      expect(
        actionFailureMessage('rename tab', _Opaque()),
        'Could not rename tab. $unknownErrorMessage',
      );
    });
  });

  test('runtime writes translate only transport timeouts', () {
    expect(
      runtimeActionErrorMessage(TimeoutException('slow')),
      'The runtime did not answer in time.',
    );
    expect(
      runtimeActionErrorMessage(RuntimeRequestError('Push first.')),
      'Push first.',
    );
  });

  group('showActionFailure', () {
    late List<LogRecord> records;
    late StreamSubscription<LogRecord> subscription;

    setUp(() {
      records = <LogRecord>[];
      subscription = Logger.root.onRecord.listen(records.add);
    });

    tearDown(() => subscription.cancel());

    testWidgets('logs the failure and shows the cause', (tester) async {
      final messengerKey = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messengerKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      final error = StateError('tab not found');
      final stackTrace = StackTrace.current;

      showActionFailure(
        messengerKey.currentState,
        action: 'close tab',
        error: error,
        stackTrace: stackTrace,
      );
      await tester.pump();

      expect(find.text('Could not close tab: Tab not found'), findsOneWidget);
      final record = records.singleWhere(
        (r) => r.loggerName == 'ActionFailure',
      );
      expect(record.level, Level.WARNING);
      expect(record.message, 'could not close tab');
      expect(record.error, same(error));
      expect(record.stackTrace, same(stackTrace));
    });

    test('still logs without a messenger', () {
      showActionFailure(null, action: 'export logs', error: StateError('x'));
      expect(
        records.where((r) => r.loggerName == 'ActionFailure').single.message,
        'could not export logs',
      );
    });
  });
}
