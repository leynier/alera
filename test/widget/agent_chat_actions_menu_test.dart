import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_footer_actions.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';

final class _NativeHistory extends AgentChatNativeHistoryRepository {
  final List<bool> configured = <bool>[];

  @override
  Future<AgentChatSnapshot> configureFileCheckpoints(
    AgentChatRef chat, {
    required String requestId,
    required bool enabled,
  }) async {
    configured.add(enabled);
    return agentChatSnapshotFixture();
  }
}

/// A runtime that offers file checkpoints and nothing else optional.
final class _Lifecycle extends AgentChatLifecycleRepository
    implements AgentChatNativeHistoryAccess {
  @override
  final _NativeHistory nativeHistory = _NativeHistory();

  @override
  Future<bool> supports(String capability) async =>
      capability == AgentChatWire.fileCheckpointsCapability;
}

const Map<String, Object?> _checkpointCapabilities = <String, Object?>{
  'interrupt': true,
  'nativeHistory': <String, Object?>{'fileCheckpointing': true},
};

Future<_Lifecycle> _pump(WidgetTester tester, {bool busy = false}) async {
  final lifecycle = _Lifecycle();
  final repository = FakeAgentChatRepository()
    ..snapshots.add(
      () => agentChatSnapshotFixture(
        status: busy ? 'running' : 'ready',
        activeTurnId: busy ? 'turn-1' : null,
        capabilities: _checkpointCapabilities,
      ),
    );
  var nextId = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatLifecycleRepositoryProvider.overrideWithValue(lifecycle),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
        chatTasksSupportedProvider.overrideWith((ref) async => false),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: const Scaffold(
          body: Center(
            child: AgentChatActionsMenu(chatId: 'chat-1', workspaceId: 'ws-1'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return lifecycle;
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('agent-chat-actions')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('turning file checkpointing on says what it records', (
    tester,
  ) async {
    final lifecycle = await _pump(tester);
    await _openMenu(tester);
    await tester.tap(find.text('File Checkpointing'));
    await tester.pumpAndSettle();
    expect(find.text('Turn On File Checkpointing?'), findsOneWidget);
    await tester.tap(find.text('Turn On'));
    await tester.pumpAndSettle();
    expect(lifecycle.nativeHistory.configured, <bool>[true]);
  });

  testWidgets('cancelling the notice changes nothing', (tester) async {
    final lifecycle = await _pump(tester);
    await _openMenu(tester);
    await tester.tap(find.text('File Checkpointing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(lifecycle.nativeHistory.configured, isEmpty);
  });

  testWidgets('a running turn keeps checkpointing until it ends', (
    tester,
  ) async {
    final lifecycle = await _pump(tester, busy: true);
    await _openMenu(tester);
    expect(find.text('Available once this turn ends'), findsOneWidget);
    await tester.tap(find.text('File Checkpointing'));
    await tester.pumpAndSettle();
    expect(find.text('Turn On File Checkpointing?'), findsNothing);
    expect(lifecycle.nativeHistory.configured, isEmpty);
  });
}
