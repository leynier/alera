import 'dart:async';

import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/application/chat_workspace_attention.dart';
import 'package:alera/src/features/chat_tasks/domain/chat_attention_entry.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Foreground implements AppForeground {
  bool visible = true;
  final StreamController<bool> events = StreamController<bool>.broadcast();

  @override
  bool get isForeground => visible;

  @override
  Stream<bool> get changes => events.stream;

  void setVisible(bool value) {
    visible = value;
    events.add(value);
  }

  @override
  void dispose() => unawaited(events.close());
}

final class _TaskRepository implements AgentChatOrchestrationRepository {
  int supportReads = 0;
  int watchStarts = 0;
  final StreamController<AgentChatTaskPage> open =
      StreamController<AgentChatTaskPage>.broadcast();
  final StreamController<AgentChatTaskPage> attention =
      StreamController<AgentChatTaskPage>.broadcast();

  @override
  Future<bool> supported() async {
    supportReads++;
    return true;
  }

  @override
  Stream<AgentChatTaskPage> watchTasks(AgentChatTaskQuery query) {
    watchStarts++;
    return query.attention == true ? attention.stream : open.stream;
  }

  Future<void> dispose() async {
    await Future.wait<void>(<Future<void>>[open.close(), attention.close()]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'shared chat attention survives resubscription and tears down at exit',
    () async {
      final foreground = _Foreground();
      final repository = _TaskRepository();
      final container = ProviderContainer(
        overrides: [
          appForegroundProvider.overrideWithValue(foreground),
          chatTaskRepositoryProvider.overrideWithValue(repository),
          chatAttentionEntriesProvider.overrideWithValue(
            <String, ChatAttentionEntry>{
              'parent': ChatAttentionEntry(
                chatId: 'parent',
                workspaceId: 'ws-1',
                title: 'Parent',
                updatedAt: DateTime.utc(2026),
              ),
            },
          ),
        ],
      );
      var disposed = false;
      addTearDown(() async {
        if (!disposed) container.dispose();
        foreground.dispose();
        await repository.dispose();
      });
      var listener = container.listen(
        chatWorkspaceAttentionProvider,
        (_, _) {},
      );
      await pumpEventQueue();
      expect(repository.supportReads, 1);
      expect(repository.watchStarts, 2);
      repository.open.add(
        AgentChatTaskPage(
          tasks: <AgentChatTask>[
            AgentChatTask(
              id: 'child-task',
              status: AgentChatTaskStatus.needsInput,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
              parentChatId: 'parent',
              childChatId: 'child',
            ),
          ],
        ),
      );
      await pumpEventQueue();
      expect(listener.read()['ws-1']!.level, ChatAttentionLevel.needsInput);

      listener.close();
      await container.pump();
      listener = container.listen(chatWorkspaceAttentionProvider, (_, _) {});
      await pumpEventQueue();
      expect(repository.supportReads, 1);
      expect(repository.watchStarts, 2);
      expect(listener.read()['ws-1']!.level, ChatAttentionLevel.needsInput);

      foreground.setVisible(false);
      await pumpEventQueue();
      expect(repository.open.hasListener, isFalse);
      expect(repository.attention.hasListener, isFalse);
      foreground.setVisible(true);
      await pumpEventQueue();
      expect(repository.watchStarts, 4);
      expect(repository.open.hasListener, isTrue);
      expect(repository.attention.hasListener, isTrue);

      container.dispose();
      disposed = true;
      await pumpEventQueue();
      expect(repository.open.hasListener, isFalse);
      expect(repository.attention.hasListener, isFalse);
      expect(foreground.events.hasListener, isFalse);
    },
  );
}
