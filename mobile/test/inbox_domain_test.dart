import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/inbox/domain/inbox_models.dart';
import 'package:alera_mobile/src/features/inbox/infra/mobile_runtime_inbox_repository.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_labels.dart';
import 'package:alera_mobile/src/features/push_notifications/domain/push_navigation_intent.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_inbox_client.dart';

void main() {
  test('parses runtime timestamps as UTC', () {
    expect(
      parseInboxTimestamp('2026-10-06 10:00:00'),
      DateTime.utc(2026, 10, 6, 10),
    );
    expect(
      parseInboxTimestamp('2026-10-06T10:00:00Z'),
      DateTime.utc(2026, 10, 6, 10),
    );
    expect(parseInboxTimestamp(null), isNull);
    expect(parseInboxTimestamp('soon'), isNull);
  });

  test('parses threads, messages and recipients from runtime JSON', () {
    final thread = InboxThread.fromJson(inboxThreadJson(unread: 2));
    expect(thread.status, InboxQuestionStatus.delivered);
    expect(thread.unreadReplyCount, 2);
    expect(thread.recipientLabel, 'claude · Fix Login');
    expect(thread.origin!.label, 'Alera mobile on Pixel');
    expect(
      InboxOrigin.fromJson(const <String, Object?>{
        'surface': 'mcp',
        'clientId': 'claude-code',
      }).label,
      'claude-code (MCP)',
    );
    expect(const InboxOrigin(surface: 'mcp').label, 'MCP client');
    expect(thread.target.workspaceName, 'auth');

    final detail = InboxThreadDetail.fromJson(<String, Object?>{
      'thread': inboxThreadJson(),
      'messages': <Object?>[
        inboxMessageJson(),
        inboxMessageJson(
          id: 'msg_2',
          kind: 'reply',
          status: null,
          from: 'claude-term',
          to: 'ext:user',
          body: 'login_test.dart',
          sequence: 11,
          replyToId: 'msg_1',
        ),
      ],
      'recipient': inboxTargetJson(deliveryMode: 'check'),
    });
    expect(detail.messages.first.isQuestion, isTrue);
    expect(detail.messages.first.status, InboxQuestionStatus.pending);
    expect(detail.messages.last.kind, InboxMessageKind.reply);
    expect(detail.messages.last.replyToId, 'msg_1');
    expect(detail.latestQuestion!.id, 'msg_1');
    expect(detail.recipient!.deliveryMode, InboxDeliveryMode.check);
  });

  test('unknown statuses and kinds degrade safely', () {
    expect(InboxQuestionStatus.parse('later'), InboxQuestionStatus.unknown);
    expect(InboxQuestionStatus.parse('unknown'), InboxQuestionStatus.unknown);
    expect(InboxMessageKind.parse('other'), InboxMessageKind.message);
    expect(InboxDeliveryMode.parse(null), InboxDeliveryMode.unavailable);
  });

  test('labels describe ages and expiry', () {
    final now = DateTime.utc(2026, 10, 6, 12);
    expect(
      inboxAgeLabel(now.subtract(const Duration(minutes: 5)), now),
      '5m ago',
    );
    expect(inboxAgeLabel(DateTime.utc(2026, 9, 1, 12), now), '2026-09-01');
    expect(
      inboxExpiryLabel(now.add(const Duration(hours: 4, minutes: 20)), now),
      'Expires in 4h 20m',
    );
    expect(inboxExpiryLabel(now, now), 'Expires now');
  });

  test('filters threads by inbox and status', () {
    final threads = <InboxThread>[
      InboxThread.fromJson(inboxThreadJson()),
      InboxThread.fromJson(
        inboxThreadJson(threadId: 'msg_2', inbox: 'ext:ci', status: 'answered'),
      ),
    ];
    expect(
      visibleInboxThreads(threads, const MobileInboxListState(inbox: 'ext:ci')),
      hasLength(1),
    );
    expect(
      visibleInboxThreads(
        threads,
        const MobileInboxListState(status: InboxQuestionStatus.delivered),
      ).single.threadId,
      'msg_1',
    );
  });

  test('repository sends the runtime contract', () async {
    final client = FakeInboxClient();
    addTearDown(client.dispose);
    final repository = MobileRuntimeInboxRepository(client);
    await repository.thread('msg_1');
    expect(client.callsOf('inbox.thread').single.payload, <String, Object?>{
      'threadId': 'msg_1',
    });
    final result = await repository.ask(
      to: 'claude-term',
      body: 'Risky?',
      subject: '  ',
    );
    expect(result.threadId, 'msg_new');
    expect(client.callsOf('inbox.ask').single.payload, <String, Object?>{
      'inbox': 'ext:user',
      'body': 'Risky?',
      'to': 'claude-term',
    });
    await repository.ask(body: 'And?', threadId: 'msg_1');
    expect(client.callsOf('inbox.ask').last.payload['threadId'], 'msg_1');
    expect(client.callsOf('inbox.ask').last.payload.containsKey('to'), isFalse);
    expect(
      client.callsOf('inbox.ask').last.payload.containsKey('inbox'),
      isFalse,
    );
    expect(await repository.purge('ext:user'), 2);
    await repository.threads(status: InboxQuestionStatus.answered);
    expect(
      client.callsOf('inbox.threads').single.payload['status'],
      'answered',
    );
  });

  test('providers reload when the runtime announces an inbox change', () async {
    final client = FakeInboxClient();
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        mobileInboxClientProvider('host').overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      mobileInboxThreadsProvider('host'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    expect(
      (await container.read(mobileInboxThreadsProvider('host').future)).items,
      hasLength(1),
    );
    client.threads = <Map<String, Object?>>[
      inboxThreadJson(),
      inboxThreadJson(threadId: 'msg_2'),
    ];
    client.emit('automationsChanged');
    await Future<void>.delayed(Duration.zero);
    expect(client.callsOf('inbox.threads'), hasLength(1));
    client.emit(inboxChangedEvent, <String, Object?>{'revision': 4});
    await Future<void>.delayed(Duration.zero);
    expect(
      (await container.read(mobileInboxThreadsProvider('host').future)).items,
      hasLength(2),
    );
    expect(client.callsOf('inbox.threads'), hasLength(2));
  });

  test(
    'push intents route inbox replies to their thread, never a terminal',
    () {
      final intent = PushNavigationIntent.fromData(<String, Object?>{
        'runtimeId': 'runtime-1',
        'workspaceId': 'ws-1',
        'kind': 'inboxReply',
        'category': 'attention',
        'threadId': 'msg_1',
        'messageId': 'msg_2',
        'tabId': 'tab-1',
      });
      expect(intent.eventKind, PushEventKind.inboxReply);
      expect(intent.threadId, 'msg_1');
      expect(intent.shouldOpenTerminal, isFalse);
      expect(intent.toJson()['threadId'], 'msg_1');
      expect(PushEventKind.parse('inbox_reply'), PushEventKind.inboxReply);
    },
  );

  test('thread pages merge by activity and restart on a change', () async {
    final client = FakeInboxClient()
      ..threads = <Map<String, Object?>>[
        for (var index = 0; index < inboxThreadPageSize + 5; index++)
          inboxThreadJson(threadId: 'msg_$index', lastSequence: 1000 - index),
      ];
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        mobileInboxClientProvider('host').overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    final provider = mobileInboxThreadsProvider('host');
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final first = await container.read(provider.future);
    expect(first.items, hasLength(inboxThreadPageSize));
    expect(first.nextBefore, 1000 - inboxThreadPageSize + 1);

    await container.read(provider.notifier).loadMore();
    final merged = container.read(provider).value!;
    expect(merged.items, hasLength(inboxThreadPageSize + 5));
    expect(merged.items.last.threadId, 'msg_${inboxThreadPageSize + 4}');
    expect(merged.nextBefore, isNull);
    expect(
      client.callsOf('inbox.threads').last.payload['before'],
      first.nextBefore,
    );

    client.emit(inboxChangedEvent, <String, Object?>{'revision': 9});
    await Future<void>.delayed(Duration.zero);
    final restarted = await container.read(provider.future);
    expect(restarted.items, hasLength(inboxThreadPageSize));
    expect(client.callsOf('inbox.threads').last.payload['before'], isNull);
  });

  test('status and inbox filters are applied by the runtime', () async {
    final client = FakeInboxClient()
      ..threads = <Map<String, Object?>>[
        inboxThreadJson(),
        inboxThreadJson(threadId: 'msg_2', inbox: 'ext:ci', status: 'answered'),
      ];
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        mobileInboxClientProvider('host').overrideWith((ref) async => client),
      ],
    );
    addTearDown(container.dispose);
    final page = await container.read(
      mobileInboxThreadsProvider(
        'host',
        inbox: 'ext:ci',
        status: InboxQuestionStatus.answered,
      ).future,
    );
    expect(page.items.single.threadId, 'msg_2');
    expect(client.callsOf('inbox.threads').single.payload, <String, Object?>{
      'inbox': 'ext:ci',
      'status': 'answered',
      'limit': inboxThreadPageSize,
    });
  });
}
