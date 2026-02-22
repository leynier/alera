import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/application/session_timeline_reducer.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

SessionNotificationEvent _event(String method, Map<String, dynamic> params) {
  return SessionNotificationEvent(
    method: method,
    payload: <String, dynamic>{'params': params},
  );
}

void main() {
  group('session timeline reducer', () {
    test(
      'creates and updates a single assistant streaming bubble from deltas',
      () {
        var state = const SessionState();

        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-1', 'threadId': 'thread-1'},
          }),
        );

        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-1',
            'itemId': 'msg-1',
            'delta': 'Hello',
          }),
        );

        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-1',
            'itemId': 'msg-1',
            'delta': ' world',
          }),
        );

        final assistantMessages = state.timelineMessages
            .where((m) => m.role == TimelineRole.assistant)
            .toList(growable: false);

        expect(assistantMessages, hasLength(1));
        expect(assistantMessages.first.markdownText, 'Hello world');
        expect(assistantMessages.first.isStreaming, isTrue);
        expect(
          state.activeStreamingAssistantMessageId,
          assistantMessages.first.id,
        );
      },
    );

    test(
      'item completed for agent message merges final text without duplicates',
      () {
        var state = const SessionState();

        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-2', 'threadId': 'thread-1'},
          }),
        );

        state = reduceNotification(
          state,
          _event('item/agentMessage/delta', <String, dynamic>{
            'turnId': 'turn-2',
            'itemId': 'msg-2',
            'delta': 'Hola',
          }),
        );

        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-2',
            'item': <String, dynamic>{
              'id': 'msg-2',
              'type': 'agentMessage',
              'status': 'completed',
              'text': 'Hola, en que te ayudo?',
            },
          }),
        );

        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-2',
            'item': <String, dynamic>{
              'id': 'msg-2',
              'type': 'agentMessage',
              'status': 'completed',
              'text': 'Hola, en que te ayudo?',
            },
          }),
        );

        final assistantMessages = state.timelineMessages
            .where((m) => m.role == TimelineRole.assistant)
            .toList(growable: false);

        expect(assistantMessages, hasLength(1));
        expect(assistantMessages.first.markdownText, 'Hola, en que te ayudo?');
        expect(assistantMessages.first.isStreaming, isFalse);
      },
    );

    test(
      'creates assistant message from item completed when no deltas arrived',
      () {
        var state = const SessionState();

        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-fallback',
              'threadId': 'thread-1',
            },
          }),
        );

        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-fallback',
            'item': <String, dynamic>{
              'id': 'msg-fallback',
              'type': 'agentMessage',
              'status': 'completed',
              'text': 'Final answer without stream',
            },
          }),
        );

        final assistantMessages = state.timelineMessages
            .where((m) => m.role == TimelineRole.assistant)
            .toList(growable: false);

        expect(assistantMessages, hasLength(1));
        expect(assistantMessages.first.id, 'msg-fallback');
        expect(
          assistantMessages.first.markdownText,
          'Final answer without stream',
        );
        expect(assistantMessages.first.isStreaming, isFalse);
      },
    );

    test(
      'builds and updates activity items from started, delta and completed',
      () {
        var state = const SessionState();

        state = reduceNotification(
          state,
          _event('turn/started', <String, dynamic>{
            'turn': <String, dynamic>{'id': 'turn-3', 'threadId': 'thread-1'},
          }),
        );

        state = reduceNotification(
          state,
          _event('item/started', <String, dynamic>{
            'turnId': 'turn-3',
            'item': <String, dynamic>{
              'id': 'cmd-1',
              'type': 'commandExecution',
              'command': 'git status',
              'cwd': '/repo',
              'status': 'inProgress',
            },
          }),
        );

        state = reduceNotification(
          state,
          _event('item/commandExecution/outputDelta', <String, dynamic>{
            'turnId': 'turn-3',
            'itemId': 'cmd-1',
            'delta': 'On branch main\n',
          }),
        );

        state = reduceNotification(
          state,
          _event('item/completed', <String, dynamic>{
            'turnId': 'turn-3',
            'item': <String, dynamic>{
              'id': 'cmd-1',
              'type': 'commandExecution',
              'command': 'git status',
              'cwd': '/repo',
              'status': 'completed',
              'aggregatedOutput': 'On branch main\n',
            },
          }),
        );

        expect(state.timelineActivities, hasLength(1));
        final item = state.timelineActivities.first;
        expect(item.kind, ActivityKind.commandExecution);
        expect(item.status, TimelineActivityStatus.completed);
        expect(item.details, contains('On branch main'));

        expect(state.turnGroups, hasLength(1));
        expect(state.turnGroups.first.activityItemIds, contains('cmd-1'));
      },
    );

    test('turn completed closes active streaming assistant message', () {
      var state = const SessionState();

      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-4', 'threadId': 'thread-1'},
        }),
      );

      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-4',
          'itemId': 'msg-4',
          'delta': 'partial answer',
        }),
      );

      expect(state.activeStreamingAssistantMessageId, isNotNull);

      state = reduceNotification(
        state,
        _event('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-4',
            'threadId': 'thread-1',
            'status': 'completed',
          },
        }),
      );

      final assistant = state.timelineMessages.firstWhere(
        (message) => message.id == 'msg-4',
      );
      expect(assistant.isStreaming, isFalse);
      expect(state.activeStreamingAssistantMessageId, isNull);
      expect(state.activeTurnId, isNull);
    });

    test('unknown events only affect raw log and keep timeline untouched', () {
      final state = reduceNotification(
        const SessionState(),
        _event('foo/bar', <String, dynamic>{'x': 1}),
      );

      expect(state.timelineMessages, isEmpty);
      expect(state.timelineActivities, isEmpty);
      expect(state.turnGroups, isEmpty);
      expect(state.activityLog, hasLength(1));
      expect(state.activityLog.first, startsWith('foo/bar:'));
    });

    test('optimistic user message is linked to turn on turn started', () {
      var state = const SessionState();

      state = appendOptimisticUserMessage(state, text: 'implement feature x');
      expect(state.timelineMessages, hasLength(1));
      expect(state.timelineMessages.first.turnId, isNull);

      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{'id': 'turn-5', 'threadId': 'thread-1'},
        }),
      );

      expect(state.timelineMessages.first.turnId, 'turn-5');
      expect(state.turnGroups, hasLength(1));
      expect(
        state.turnGroups.first.userMessageId,
        state.timelineMessages.first.id,
      );
    });
  });
}
