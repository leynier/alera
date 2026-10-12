import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera_mobile/src/features/inbox/domain/inbox_models.dart';
import 'package:alera_mobile/src/features/inbox/infra/mobile_runtime_inbox_repository.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_compose_screen.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_delivery_labels.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:alera_mobile/src/features/runs/presentation/activity_screen.dart';
import 'package:alera_mobile/src/features/inbox/presentation/inbox_thread_screen.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_inbox_client.dart';

Widget _app(FakeInboxClient client, Widget child) => ProviderScope(
  overrides: [
    mobileInboxClientProvider('host').overrideWith((ref) async => client),
  ],
  child: MaterialApp(home: child),
);

FakeInboxClient _v2Client() =>
    FakeInboxClient(supportsInboxDelivery: true)
      ..targets = <Map<String, Object?>>[
        inboxTargetJson(
          handle: 'codex-term',
          agent: 'codex',
          tabTitle: 'Review',
          deliveryMode: 'pasted_now',
          acceptsQueuedInput: true,
        ),
        inboxTargetJson(deliveryMode: 'queued_at_turn_end'),
        inboxTargetJson(
          handle: 'coord-term',
          agent: 'claude',
          tabTitle: 'Coordinator',
          deliveryMode: 'check',
        ),
      ];

Future<void> _openCompose(
  WidgetTester tester,
  FakeInboxClient client, {
  String? preselectedHandle,
}) async {
  await tester.pumpWidget(
    _app(
      client,
      InboxComposeScreen(hostId: 'host', preselectedHandle: preselectedHandle),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _typeQuestionAndSend(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Question'),
    'Which auth flow?',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Send'));
  await tester.pumpAndSettle();
}

SegmentedButton<InboxDelivery> _deliveryButton(WidgetTester tester) =>
    tester.widget<SegmentedButton<InboxDelivery>>(
      find.byType(SegmentedButton<InboxDelivery>),
    );

void main() {
  group('domain', () {
    test('parses inboxV2 delivery modes and the legacy paste', () {
      expect(
        InboxDeliveryMode.parse('pasted_now'),
        InboxDeliveryMode.pastedNow,
      );
      expect(
        InboxDeliveryMode.parse('queued_at_turn_end'),
        InboxDeliveryMode.queuedAtTurnEnd,
      );
      expect(InboxDeliveryMode.parse('check'), InboxDeliveryMode.check);
      expect(
        InboxDeliveryMode.parse('unavailable'),
        InboxDeliveryMode.unavailable,
      );
      expect(
        InboxDeliveryMode.parse('paste'),
        InboxDeliveryMode.queuedAtTurnEnd,
      );
      expect(InboxDeliveryMode.tryParse(null), isNull);
      expect(InboxDeliveryMode.pastedNow.acceptsNow, isTrue);
      expect(InboxDeliveryMode.check.acceptsNow, isTrue);
      expect(InboxDeliveryMode.queuedAtTurnEnd.acceptsNow, isFalse);
      expect(InboxDelivery.tryParse('turn_end'), InboxDelivery.turnEnd);
    });

    test('a legacy received status reads as Delivered', () {
      expect(
        InboxQuestionStatus.parse('received'),
        InboxQuestionStatus.delivered,
      );
      final thread = InboxThread.fromJson(inboxThreadJson(status: 'received'));
      expect(thread.status.label, 'Delivered');
      expect(
        InboxQuestionStatus.filterable.map((status) => status.label),
        <String>['Pending', 'Delivered', 'Answered', 'Expired', 'Cancelled'],
      );
    });

    test('targets, messages and ask results carry delivery', () {
      final target = InboxRecipient.fromJson(
        inboxTargetJson(deliveryMode: 'pasted_now', acceptsQueuedInput: true),
      );
      expect(target.deliveryMode, InboxDeliveryMode.pastedNow);
      expect(target.acceptsQueuedInput, isTrue);

      final message = InboxMessage.fromJson(<String, Object?>{
        ...inboxMessageJson(status: 'delivered'),
        'delivery': 'now',
        'deliveredAt': '2026-10-06 10:00:20',
      });
      expect(message.delivery, InboxDelivery.now);
      expect(message.deliveredAt, DateTime.utc(2026, 10, 6, 10, 0, 20));
      expect(message.deliveredNow, isTrue);
      final late = InboxMessage.fromJson(<String, Object?>{
        ...inboxMessageJson(status: 'delivered'),
        'delivery': 'now',
        'deliveredAt': '2026-10-06 10:30:00',
      });
      expect(late.deliveredNow, isFalse);

      expect(
        InboxAskResult.fromJson(<String, Object?>{
          'questionId': 'q',
          'deliveryMode': 'queued_at_turn_end',
        }).deliveryMode,
        InboxDeliveryMode.queuedAtTurnEnd,
      );
    });

    test('the pending limit and other refusals read in plain words', () {
      expect(
        inboxErrorMessage(
          RuntimeRequestError(
            'the recipient already has 100 undelivered questions',
            code: 'inbox_pending_limit',
          ),
        ),
        'This agent already has 100 questions waiting. Wait for it to read them or cancel some.',
      );
      expect(
        inboxErrorMessage(RuntimeRequestError('host text', code: 'other')),
        'host text',
      );
      expect(inboxErrorMessage(StateError('gone')), 'gone');
    });

    test('expiry choices map to what is sent', () {
      expect(inboxExpiryToSend(const Duration(hours: 5)), isNull);
      expect(
        inboxExpiryToSend(const Duration(days: 1)),
        const Duration(days: 1),
      );
      expect(inboxExpiryChoices.map(inboxExpiryChoiceLabel), <String>[
        '1 Hour',
        '5 Hours',
        '1 Day',
        '7 Days',
      ]);
    });
  });

  group('repository', () {
    test('sends delivery only to inboxV2 hosts', () async {
      final legacy = FakeInboxClient();
      addTearDown(legacy.dispose);
      await MobileRuntimeInboxRepository(legacy)
          .ask(to: 'claude-term', body: 'Risky?', delivery: InboxDelivery.now);
      expect(
        legacy.callsOf('inbox.ask').single.payload.containsKey('delivery'),
        isFalse,
      );

      final current = FakeInboxClient(supportsInboxDelivery: true);
      addTearDown(current.dispose);
      final repository = MobileRuntimeInboxRepository(current);
      final result = await repository.ask(
        to: 'claude-term',
        body: 'Risky?',
        delivery: InboxDelivery.turnEnd,
        expiresIn: const Duration(hours: 1),
      );
      expect(current.callsOf('inbox.ask').single.payload, <String, Object?>{
        'inbox': 'ext:user',
        'body': 'Risky?',
        'to': 'claude-term',
        'expiresInMs': 3600000,
        'delivery': 'turnEnd',
      });
      expect(result.deliveryMode, InboxDeliveryMode.queuedAtTurnEnd);
      await repository.ask(
        body: 'And?',
        threadId: 'msg_1',
        delivery: InboxDelivery.now,
      );
      expect(current.callsOf('inbox.ask').last.payload['delivery'], 'now');
    });
  });

  group('compose', () {
    testWidgets('a host without inboxV2 keeps the turn-end note', (
      tester,
    ) async {
      final client = FakeInboxClient();
      addTearDown(client.dispose);
      await _openCompose(tester, client, preselectedHandle: 'claude-term');
      expect(find.text('Delivers when its turn ends'), findsWidgets);
      expect(find.byType(SegmentedButton<InboxDelivery>), findsNothing);
      expect(find.text('Advanced'), findsNothing);
      expect(find.text(inboxLegacyDeliveryNote), findsOneWidget);
      await _typeQuestionAndSend(tester);
      final ask = client.callsOf('inbox.ask').single.payload;
      expect(ask.containsKey('delivery'), isFalse);
      expect(ask.containsKey('expiresInMs'), isFalse);
    });

    testWidgets('each agent says how it receives a question and Now is the '
        'default', (tester) async {
      final client = _v2Client();
      addTearDown(client.dispose);
      await _openCompose(tester, client, preselectedHandle: 'codex-term');
      expect(find.text('Delivers now'), findsOneWidget);
      expect(find.text('Delivers when its turn ends'), findsOneWidget);
      expect(find.text('Reads on its next check'), findsOneWidget);
      expect(find.text('DELIVER'), findsOneWidget);
      expect(_deliveryButton(tester).selected, <InboxDelivery>{
        InboxDelivery.now,
      });
      expect(find.text(inboxDeliverNowHelper), findsOneWidget);
      expect(find.text(inboxLegacyDeliveryNote), findsNothing);
      await _typeQuestionAndSend(tester);
      final ask = client.callsOf('inbox.ask').single.payload;
      expect(ask['delivery'], 'now');
      expect(ask['inbox'], 'ext:user');
      expect(ask.containsKey('expiresInMs'), isFalse);
    });

    testWidgets('Now is disabled for an agent that only takes questions at '
        'the end of its turn', (tester) async {
      final client = _v2Client();
      addTearDown(client.dispose);
      await _openCompose(tester, client, preselectedHandle: 'claude-term');
      final button = _deliveryButton(tester);
      expect(
        button.segments
            .firstWhere((segment) => segment.value == InboxDelivery.now)
            .enabled,
        isFalse,
      );
      expect(button.selected, <InboxDelivery>{InboxDelivery.turnEnd});
      expect(
        find.text(
          'This agent cannot take input while it works, so it receives the question when its turn ends.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'The agent receives the question when it finishes its turn. If that does not happen within 5 hours, the question expires.',
        ),
        findsOneWidget,
      );
      await _typeQuestionAndSend(tester);
      expect(client.callsOf('inbox.ask').single.payload['delivery'], 'turnEnd');
    });

    testWidgets('Advanced sets another inbox and expiry', (tester) async {
      // Tall enough that the lazily built form shows Advanced unscrolled.
      tester.view
        ..physicalSize = const Size(800, 2000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final client = _v2Client();
      addTearDown(client.dispose);
      await _openCompose(tester, client, preselectedHandle: 'codex-term');
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Inbox'),
        'ext:review',
      );
      await tester.tap(find.text('5 Hours'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 Day').last);
      await tester.pumpAndSettle();
      // The turn-end helper follows the chosen expiry.
      await tester.tap(find.text('When the Turn Ends'));
      await tester.pumpAndSettle();
      expect(find.textContaining('within 1 day'), findsOneWidget);
      await _typeQuestionAndSend(tester);
      final ask = client.callsOf('inbox.ask').single.payload;
      expect(ask['inbox'], 'ext:review');
      expect(ask['expiresInMs'], const Duration(days: 1).inMilliseconds);
      expect(ask['delivery'], 'turnEnd');
    });
  });

  group('thread', () {
    testWidgets('the header says the question was delivered now and the '
        'follow-up offers the delivery choice', (tester) async {
      final client = _v2Client()
        ..recipient = inboxTargetJson(deliveryMode: 'pasted_now')
        ..messages['msg_1'] = <Map<String, Object?>>[
          <String, Object?>{
            ...inboxMessageJson(status: 'delivered'),
            'delivery': 'now',
            'deliveryMode': 'pasted_now',
          },
        ];
      addTearDown(client.dispose);
      await tester.pumpWidget(
        _app(
          client,
          const InboxThreadScreen(hostId: 'host', threadId: 'msg_1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delivered now'), findsOneWidget);
      expect(find.byType(SegmentedButton<InboxDelivery>), findsOneWidget);
      await tester.tap(find.text('When the Turn Ends'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'And the rollback?');
      await tester.tap(find.byTooltip('Send Follow-Up'));
      await tester.pumpAndSettle();
      final ask = client.callsOf('inbox.ask').single.payload;
      expect(ask['threadId'], 'msg_1');
      expect(ask['delivery'], 'turnEnd');
    });

    testWidgets('a coordinator thread reads on its next check', (tester) async {
      final client = _v2Client()
        ..threads = <Map<String, Object?>>[inboxThreadJson(status: 'received')]
        ..recipient = inboxTargetJson(deliveryMode: 'check');
      addTearDown(client.dispose);
      await tester.pumpWidget(
        _app(
          client,
          const InboxThreadScreen(hostId: 'host', threadId: 'msg_1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Read on its next check'), findsOneWidget);
      expect(find.text('Delivered'), findsWidgets);
      expect(find.text('Received'), findsNothing);
    });

    testWidgets('a follow-up is disabled once the terminal is gone', (
      tester,
    ) async {
      final client = _v2Client()
        ..recipient = inboxTargetJson(sessionLive: false);
      addTearDown(client.dispose);
      await tester.pumpWidget(
        _app(
          client,
          const InboxThreadScreen(hostId: 'host', threadId: 'msg_1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          "This agent's terminal is no longer running. Ask another agent with Ask Agent.",
        ),
        findsOneWidget,
      );
      expect(find.byType(SegmentedButton<InboxDelivery>), findsNothing);
      final send = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Send Follow-Up'),
          matching: find.byType(IconButton),
        ),
      );
      expect(send.onPressed, isNull);
    });
  });

  testWidgets('the status filters no longer offer Received', (tester) async {
    final client = FakeInboxClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      _app(
        client,
        const ActivityScreen(
          hostId: 'host',
          initialSection: ActivitySection.questions,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Received'), findsNothing);
    expect(find.text('Delivered'), findsWidgets);
  });
}
