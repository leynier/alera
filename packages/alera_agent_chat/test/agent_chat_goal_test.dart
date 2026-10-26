import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

import 'agent_chat_contract_transport.dart';

AgentChatGoal _goal(
  AgentChatGoalStatus status, {
  int tokensUsed = 0,
  int? tokenBudget,
  int timeUsedSeconds = 0,
}) => AgentChatGoal(
  objective: 'Ship the release',
  status: status,
  tokensUsed: tokensUsed,
  tokenBudget: tokenBudget,
  timeUsedSeconds: timeUsedSeconds,
);

AgentChatGoalPresentation _present(
  AgentChatGoal goal, {
  bool working = false,
}) => AgentChatGoalPresentation.of(goal, working: working);

void main() {
  group('parsing', () {
    test('reads a goal from the session', () {
      final session = AgentChatSession.fromJson(<String, Object?>{
        'status': 'running',
        'goal': <String, Object?>{
          'objective': '  Ship the release  ',
          'status': 'usage_limited',
          'tokensUsed': 12500,
          'tokenBudget': 50000,
          'timeUsedSeconds': 125,
        },
      });
      final goal = session.goal!;
      expect(goal.objective, 'Ship the release');
      expect(goal.status, AgentChatGoalStatus.usageLimited);
      expect(goal.tokensUsed, 12500);
      expect(goal.tokenBudget, 50000);
      expect(goal.timeUsedSeconds, 125);
    });

    test('reads every wire status', () {
      const wire = <String, AgentChatGoalStatus>{
        'active': AgentChatGoalStatus.active,
        'paused': AgentChatGoalStatus.paused,
        'blocked': AgentChatGoalStatus.blocked,
        'usage_limited': AgentChatGoalStatus.usageLimited,
        'budget_limited': AgentChatGoalStatus.budgetLimited,
        'complete': AgentChatGoalStatus.complete,
      };
      for (final entry in wire.entries) {
        expect(AgentChatGoalStatus.fromJson(entry.key), entry.value);
      }
    });

    test('absent, null, empty or malformed goals read as none', () {
      for (final goal in <Object?>[
        null,
        'Ship it',
        <String, Object?>{'status': 'active'},
        <String, Object?>{'objective': '   ', 'status': 'active'},
      ]) {
        expect(
          AgentChatSession.fromJson(<String, Object?>{'goal': goal}).goal,
          isNull,
        );
      }
      expect(AgentChatSession.fromJson(<String, Object?>{}).goal, isNull);
    });

    test('an unknown status reads as paused and optional fields default', () {
      final goal = AgentChatGoal.tryParse(<String, Object?>{
        'objective': 'Ship it',
        'status': 'paused_by_policy',
        'tokenBudget': null,
      })!;
      expect(goal.status, AgentChatGoalStatus.paused);
      expect(goal.tokensUsed, 0);
      expect(goal.tokenBudget, isNull);
      expect(goal.timeUsedSeconds, 0);
      expect(_present(goal).canResume, isTrue);
    });

    test('a turn reads its origin', () {
      final continuation = AgentChatTurn.fromJson(<String, Object?>{
        'turnId': 't1',
        'status': 'running',
        'origin': 'goalContinuation',
      });
      final prompted = AgentChatTurn.fromJson(<String, Object?>{
        'turnId': 't2',
        'status': 'running',
      });
      expect(continuation.origin, 'goalContinuation');
      expect(continuation.goalContinuation, isTrue);
      expect(prompted.origin, isNull);
      expect(prompted.goalContinuation, isFalse);
      final background = AgentChatTurn.fromJson(<String, Object?>{
        'turnId': 't3',
        'status': 'running',
        'origin': 'backgroundContinuation',
      });
      expect(background.backgroundContinuation, isTrue);
      expect(background.goalContinuation, isFalse);
      expect(continuation.backgroundContinuation, isFalse);
    });

    test('a continuation turn without a prompt marks its section', () {
      final thread = AgentChatThread.fromSnapshot(
        AgentChatSnapshot.fromJson(<String, Object?>{
          'chatId': 'chat-1',
          'workspaceId': 'ws-1',
          'cursor': 1,
          'turns': <Object?>[
            <String, Object?>{
              'turnId': 't1',
              'status': 'completed',
              'origin': 'goalContinuation',
            },
            <String, Object?>{'turnId': 't2', 'status': 'completed'},
          ],
          'items': <Object?>[
            for (final turnId in <String>['t1', 't2'])
              <String, Object?>{
                'itemId': 'a-$turnId',
                'turnId': turnId,
                'type': 'assistant_message',
                'status': 'completed',
                'createdAt': '2026-10-12T10:00:00Z',
                'updatedAt': '2026-10-12T10:00:00Z',
                'text': 'Done.',
              },
          ],
        }),
      );
      final sections = <AgentChatTurnSection>[
        for (final entry in AgentChatTimelineProjection.build(
          thread,
        ).entries.whereType<AgentChatTurnEntry>())
          entry.section,
      ];
      expect(sections.map((section) => section.goalContinuation), <bool>[
        true,
        false,
      ]);
      expect(sections.map((section) => section.backgroundContinuation), <bool>[
        false,
        false,
      ]);
    });
  });

  group('presentation', () {
    test('titles each status', () {
      const titles = <AgentChatGoalStatus, String>{
        AgentChatGoalStatus.paused: 'Goal paused',
        AgentChatGoalStatus.blocked: 'Goal blocked',
        AgentChatGoalStatus.usageLimited: 'Goal hit a usage limit',
        AgentChatGoalStatus.budgetLimited: 'Goal reached its token budget',
        AgentChatGoalStatus.complete: 'Goal complete',
      };
      for (final entry in titles.entries) {
        expect(_present(_goal(entry.key)).title, entry.value);
        expect(_present(_goal(entry.key), working: true).title, entry.value);
      }
    });

    test('an active goal is pursued only while the chat works', () {
      final active = _goal(AgentChatGoalStatus.active);
      expect(_present(active, working: true).title, 'Pursuing goal');
      expect(_present(active).title, 'Goal set');
    });

    test('formats tokens as T3 Code does', () {
      const labels = <int, String>{
        0: '0',
        999: '999',
        1000: '1k',
        12499: '12k',
        12500: '13k',
        999499: '999k',
        1000000: '1m',
        1250000: '1.3m',
        1500000: '1.5m',
        2000000: '2m',
        12340000: '12.3m',
      };
      for (final entry in labels.entries) {
        expect(agentChatGoalTokenLabel(entry.key), entry.value);
      }
    });

    test('joins tokens, budget and elapsed time', () {
      expect(_present(_goal(AgentChatGoalStatus.active)).usage, isNull);
      final tokens = _present(
        _goal(AgentChatGoalStatus.active, tokensUsed: 950),
      );
      expect(tokens.usage, '950 tokens');
      expect(tokens.heading, 'Goal set · 950 tokens');
      expect(
        _present(
          _goal(
            AgentChatGoalStatus.paused,
            tokensUsed: 12500,
            tokenBudget: 50000,
            timeUsedSeconds: 125,
          ),
        ).usage,
        '13k / 50k tokens · 2m 5s',
      );
    });

    test('elapsed time shows from one minute', () {
      expect(
        _present(_goal(AgentChatGoalStatus.paused, timeUsedSeconds: 59)).usage,
        isNull,
      );
      final minute = _present(
        _goal(AgentChatGoalStatus.paused, timeUsedSeconds: 60),
      );
      expect(minute.usage, '1m');
      expect(minute.heading, 'Goal paused · 1m');
      expect(
        _present(_goal(AgentChatGoalStatus.paused, timeUsedSeconds: 3720))
            .usage,
        '1h 2m',
      );
    });

    test('resumes every goal that is neither active nor complete', () {
      for (final status in AgentChatGoalStatus.values) {
        expect(
          _present(_goal(status)).canResume,
          status != AgentChatGoalStatus.active &&
              status != AgentChatGoalStatus.complete,
          reason: status.name,
        );
      }
      expect(
        _present(_goal(AgentChatGoalStatus.paused)).objective,
        'Ship the release',
      );
    });
  });

  test(
    'a snapshot and a change carry the goal through the repository',
    () async {
      final transport = AgentChatContractTransport();
      transport.responses[AgentChatWire.snapshot] = <String, Object?>{
        ...agentChatContractSnapshot(),
        'session': <String, Object?>{
          'status': 'running',
          'activeTurnId': 't1',
          'goal': <String, Object?>{
            'objective': 'Ship the release',
            'status': 'active',
            'tokensUsed': 1200,
          },
        },
      };
      final repository = RuntimeAgentChatRepository(transport);
      const chat = AgentChatRef(chatId: 'c', workspaceId: 'w');
      final received = <AgentChatStreamEvent>[];
      final subscription = repository.watch('c').listen(received.add);
      final snapshot = await repository.snapshot(chat);
      var thread = AgentChatThread.fromSnapshot(snapshot);
      expect(thread.session.goal?.status, AgentChatGoalStatus.active);
      expect(thread.session.goal?.tokensUsed, 1200);

      transport.controller
        ..add(
          const AgentChatTransportEvent(AgentChatWire.changedEvent, {
            'chatId': 'c',
            'workspaceId': 'w',
            'cursor': 4,
            'delta': <String, Object?>{
              'session': <String, Object?>{
                'status': 'ready',
                'goal': <String, Object?>{
                  'objective': 'Ship the release',
                  'status': 'paused',
                  'tokensUsed': 1500,
                  'tokenBudget': 10000,
                },
              },
              'turns': <Object?>[
                <String, Object?>{
                  'turnId': 't2',
                  'status': 'completed',
                  'origin': 'goalContinuation',
                },
              ],
            },
          }),
        )
        ..add(
          const AgentChatTransportEvent(AgentChatWire.changedEvent, {
            'chatId': 'c',
            'workspaceId': 'w',
            'cursor': 5,
            'delta': <String, Object?>{
              'session': <String, Object?>{'status': 'ready', 'goal': null},
            },
          }),
        );
      await Future.pause(Duration.zero);
      await subscription.cancel();
      expect(received, hasLength(2));
      for (final event in received) {
        final outcome = thread.apply((event as AgentChatChangeReceived).change);
        thread = (outcome as AgentChatApplied).thread;
        if (thread.cursor == 4) {
          final goal = thread.session.goal!;
          expect(goal.status, AgentChatGoalStatus.paused);
          expect(goal.tokenBudget, 10000);
          expect(thread.turnById('t2')?.goalContinuation, isTrue);
        }
      }
      expect(thread.cursor, 5);
      expect(thread.session.goal, isNull);
      expect(transport.requests.single.$1, AgentChatWire.snapshot);
    },
  );
}
