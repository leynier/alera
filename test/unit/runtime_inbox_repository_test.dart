import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/inbox/infra/runtime_inbox_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/inbox_test_client.dart';

void main() {
  late InboxTestClient client;
  late RuntimeChangeCoalescer coalescer;
  late RuntimeInboxRepository repository;

  setUp(() {
    client = InboxTestClient();
    coalescer = RuntimeChangeCoalescer(
      debounce: const Duration(milliseconds: 1),
      maxDelay: const Duration(milliseconds: 50),
    );
    repository = RuntimeInboxRepository(client, coalescer);
  });
  tearDown(() async {
    coalescer.dispose();
    await client.events.close();
  });

  test('summary, threads and a thread parse the host payloads', () async {
    client.respond('inbox.summary', <String, Object?>{
      'kind': 'inboxes',
      'items': [
        {
          'inbox': 'ext:user',
          'threadCount': 2,
          'pendingCount': 1,
          'awaitingReplyCount': 0,
          'unreadReplyCount': 3,
          'lastActivityAt': '2026-10-06 10:05:00',
        },
        {'inbox': 'ext:ci', 'unreadReplyCount': 2},
      ],
      'revision': 7,
    });
    final summary = await repository.readSummary();
    expect(summary.unreadReplyCount, 5);
    expect(summary.revision, 7);
    expect(
      summary.inboxes.first.lastActivityAt,
      DateTime.utc(2026, 10, 6, 10, 5),
    );

    client.respond('inbox.threads', <String, Object?>{
      'items': [inboxThreadJson(status: 'answered', unread: 1)],
      'nextBefore': 4,
      'revision': 7,
    });
    final page = await repository.readThreads(
      const InboxThreadQuery(
        inbox: 'ext:user',
        status: InboxQuestionStatus.answered,
      ),
    );
    expect(client.calls.last.$2, {
      'inbox': 'ext:user',
      'status': 'answered',
      'limit': 100,
    });
    final thread = page.items.single;
    expect(thread.status, InboxQuestionStatus.answered);
    expect(thread.origin?.label, 'Alera mobile, Pixel');
    expect(thread.target.tabTitle, 'Fix Login');
    expect(page.nextBefore, 4);

    client.respond(
      'inbox.thread',
      inboxDetailJson(
        status: 'pending',
        deliveryMode: 'check',
        messages: [
          inboxMessageJson(
            kind: 'question',
            id: 'msg_q1',
            body: 'Q',
            status: 'pending',
            expiresAt: '2026-10-06 15:00:00',
          ),
          inboxMessageJson(
            kind: 'reply',
            id: 'msg_r1',
            body: 'A',
            from: 'term-1',
            to: 'ext:user',
          ),
        ],
      ),
    );
    final detail = await repository.readThread('msg_q1', markRead: true);
    expect(client.calls.last.$2, {'threadId': 'msg_q1', 'markRead': true});
    expect(detail.recipient.deliveryMode, InboxDeliveryMode.check);
    expect(detail.latestQuestion?.id, 'msg_q1');
    expect(detail.messages.last.kind, InboxMessageKind.reply);
    expect(detail.messages.first.expiresAt, DateTime.utc(2026, 10, 6, 15));
  });

  test('ask sends only what the user chose', () async {
    client.respond('inbox.ask', <String, Object?>{'threadId': 'msg_q9'});
    final threadId = await repository.ask(
      const InboxAskRequest(
        body: 'Status?',
        inbox: 'ext:user',
        to: 'term-1',
        subject: '  ',
        expiresIn: Duration(hours: 1),
      ),
    );
    expect(threadId, 'msg_q9');
    expect(client.calls.single.$2, {
      'body': 'Status?',
      'inbox': 'ext:user',
      'to': 'term-1',
      'expiresInMs': 3600000,
    });
    await repository.ask(
      const InboxAskRequest(body: 'And?', threadId: 'msg_q9'),
    );
    expect(client.calls.last.$2, {'body': 'And?', 'threadId': 'msg_q9'});
  });

  test('an old host fails closed before any request', () async {
    client.supported = false;
    await expectLater(
      repository.readSummary(),
      throwsA(isA<InboxUpdateRequired>()),
    );
    expect(client.calls, isEmpty);
    expect(
      inboxErrorMessage(const InboxUpdateRequired()),
      'Update the runtime to use the inbox.',
    );
  });

  test('watchers refresh on inboxChanged and report disconnects', () async {
    var revision = 1;
    client.handlers['inbox.summary'] = (_) => <String, Object?>{
      'items': const <Object?>[],
      'revision': revision++,
    };
    final values = <Object>[];
    final subscription = repository.watchSummary().listen(
      (summary) => values.add(summary.revision),
      onError: values.add,
    );
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    client.emit('inboxChanged');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    client.emit('workspacesChanged');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    client.emit(aleraRuntimeHostDisconnectedEvent);
    await pumpEventQueue();
    await subscription.cancel();
    expect(values.take(2), [1, 2]);
    expect(values.last, isA<TerminalHostConnectionClosedException>());
    expect(values, hasLength(3));
  });

  test('host error codes become sentence-case messages', () {
    expect(
      inboxErrorMessage(
        const TerminalHostConflictException(
          code: 'inbox_pending_limit',
          message: 'limit',
        ),
      ),
      startsWith('This agent already has 20 questions waiting'),
    );
    expect(
      inboxErrorMessage(
        const TerminalHostConflictException(code: 'other', message: 'Raw.'),
      ),
      'Raw.',
    );
  });
}
