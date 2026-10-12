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
    expect(InboxDeliveryMode.tryParse(null), isNull);
    expect(parseInboxTimestamp(''), isNull);
    expect(
      parseInboxTimestamp('2026-10-06T10:00:00Z'),
      DateTime.utc(2026, 10, 6, 10),
    );
    expect(const InboxOrigin(surface: 'desktop').label, 'Alera desktop');
    expect(const InboxOrigin(surface: 'mobile').label, 'Alera mobile');
    expect(const InboxOrigin(surface: 'cli').label, 'CLI');
    expect(
      InboxOrigin.fromJson(const <String, Object?>{
        'surface': 'mcp',
        'clientId': 'chatgpt',
        'clientName': 'ChatGPT',
      }).label,
      'ChatGPT (MCP)',
    );
    expect(const InboxOrigin(surface: 'mcp').label, 'MCP client');
    expect(InboxQuestionStatus.delivered.open, isTrue);
    expect(InboxQuestionStatus.answered.open, isFalse);
  });

  test(
    'inboxV2 delivery values parse, and legacy values keep their meaning',
    () {
      expect(
        InboxQuestionStatus.parse('received'),
        InboxQuestionStatus.delivered,
      );
      expect(
        InboxDeliveryMode.parse('paste'),
        InboxDeliveryMode.queuedAtTurnEnd,
      );
      for (final mode in InboxDeliveryMode.values) {
        expect(InboxDeliveryMode.parse(mode.key), mode);
      }
      expect(InboxDeliveryMode.queuedAtTurnEnd.acceptsNow, isFalse);
      expect(InboxDeliveryMode.unavailable.acceptsNow, isFalse);
      expect(InboxDeliveryMode.pastedNow.acceptsNow, isTrue);
      expect(InboxDelivery.tryParse('turnEnd'), InboxDelivery.turnEnd);
      expect(InboxDelivery.tryParse('later'), isNull);
      expect(
        const InboxAskRequest(body: 'Q', delivery: InboxDelivery.now).toJson(),
        {'body': 'Q'},
      );
      expect(
        const InboxAskRequest(
          body: 'Q',
          delivery: InboxDelivery.now,
        ).toJson(includeDelivery: true),
        {'body': 'Q', 'delivery': 'now'},
      );

      final target = InboxRecipient.fromJson(const {
        'handle': 'term-1',
        'deliveryMode': 'queued_at_turn_end',
        'acceptsQueuedInput': false,
      });
      expect(target.deliveryMode, InboxDeliveryMode.queuedAtTurnEnd);
      expect(target.acceptsQueuedInput, isFalse);

      final asked = InboxMessage.fromJson(const {
        'kind': 'question',
        'status': 'delivered',
        'delivery': 'now',
        'deliveredAt': '2026-10-06 10:00:20',
        'message': {'id': 'q', 'created_at': '2026-10-06 10:00:00'},
      });
      expect(asked.delivery, InboxDelivery.now);
      expect(asked.deliveredNow, isTrue);
      final late = InboxMessage.fromJson(const {
        'kind': 'question',
        'message': {
          'id': 'q',
          'delivery': 'now',
          'created_at': '2026-10-06 10:00:00',
          'delivered_at': '2026-10-06 10:30:00',
        },
      });
      expect(late.delivery, InboxDelivery.now);
      expect(late.deliveredNow, isFalse);
    },
  );

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
