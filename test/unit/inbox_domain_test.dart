import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unknown values fall back to safe defaults', () {
    expect(InboxMessageKind.parse('future'), InboxMessageKind.message);
    expect(InboxQuestionStatus.parse(null), InboxQuestionStatus.pending);
    expect(InboxDeliveryMode.parse(7), InboxDeliveryMode.unavailable);
    expect(parseInboxTimestamp(''), isNull);
    expect(
      parseInboxTimestamp('2026-10-06T10:00:00Z'),
      DateTime.utc(2026, 10, 6, 10),
    );
    expect(const InboxOrigin(surface: 'desktop').label, 'Alera desktop');
    expect(const InboxOrigin(surface: 'mobile').label, 'Alera mobile');
    expect(const InboxOrigin(surface: 'cli').label, 'CLI');
    expect(InboxQuestionStatus.delivered.open, isTrue);
    expect(InboxQuestionStatus.answered.open, isFalse);
  });

  test('every host error code has a sentence-case message', () {
    for (final code in <String>[
      'inbox_pending_limit',
      'inbox_ambiguous_recipient',
      'inbox_no_recipient',
      'inbox_unknown_recipient',
      'inbox_thread_mismatch',
      'inbox_not_cancellable',
      'inbox_question_not_found',
      'inbox_thread_not_found',
      'inbox_invalid_address',
      'inbox_invalid_expiry',
      'message_too_large',
    ]) {
      final message = inboxErrorMessage(
        TerminalHostConflictException(code: code, message: code),
      );
      expect(message, isNot(code));
      expect(message, endsWith('.'));
    }
    expect(
      inboxErrorMessage(const TerminalHostConnectionClosedException()),
      'The Alera runtime is not reachable.',
    );
    expect(inboxErrorMessage(StateError('Boom')), contains('Boom'));
    // A runtime const instance, so the constructor line is covered.
    // ignore: prefer_const_constructors
    expect(
      InboxUpdateRequired().toString(),
      'Update the runtime to use the inbox.',
    );
  });
}
