import 'dart:convert';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';

const String _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const String _id = '26ff2908-0cbd-4c5b-ad34-a8900ee80204';

final Workspace _workspace = Workspace(
  id: 'ws-1',
  projectId: 'project-1',
  name: 'Alera',
  path: '/projects/alera',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  kind: WorkspaceKind.main,
  status: WorkspaceStatus.active,
);

/// Serves [_png] for `agentChat.attachment.read` when [supported].
final class _Lifecycle extends AgentChatLifecycleRepository {
  _Lifecycle({this.supported = true, this.fails = false});

  final bool supported;
  final bool fails;
  final List<(AgentChatRef, String)> reads = <(AgentChatRef, String)>[];

  @override
  Future<bool> supports(String capability) async =>
      supported && capability == AgentChatWire.attachmentReadCapability;

  @override
  Future<AgentChatAttachmentChunk> attachment(
    AgentChatRef chat, {
    required String attachmentId,
    int offset = 0,
    int? length,
  }) async {
    reads.add((chat, attachmentId));
    if (fails) throw StateError('host offline');
    final bytes = base64Decode(_png);
    return AgentChatAttachmentChunk.fromJson(<String, Object?>{
      'attachmentId': attachmentId,
      'mimeType': 'image/png',
      'sizeBytes': bytes.length,
      'offset': 0,
      'nextOffset': bytes.length,
      'dataBase64': _png,
    });
  }
}

Map<String, Object?> _attachment({String? attachmentId = _id}) =>
    <String, Object?>{
      'type': 'localImage',
      // The host's copy, on a remote host: not on this machine.
      'path': '/remote-host/agent-chat-attachments/$_id.data.png',
      'name': 'photo.png',
      'sizeBytes': 70,
      'attachmentId': ?attachmentId,
    };

Future<void> _pump(
  WidgetTester tester,
  _Lifecycle lifecycle,
  Map<String, Object?> attachment,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = FakeAgentChatRepository()
    ..snapshots.add(
      () => agentChatSnapshotFixture(
        items: <Map<String, Object?>>[
          <String, Object?>{
            ...agentChatItemFixture('u1', 'user_message', text: 'Look'),
            'attachments': <Map<String, Object?>>[attachment],
          },
        ],
      ),
    );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatLifecycleRepositoryProvider.overrideWithValue(lifecycle),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id'),
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 12, 10),
        ),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: AgentChatSurface(
            chatId: 'chat-1',
            workspace: _workspace,
            fallbackTitle: 'Agent Chat',
            fallbackProvider: 'codex',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  // The host path is not on this machine; let the file read fail for real.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  for (var index = 0; index < 4; index += 1) {
    await tester.pump();
  }
}

final Finder _hostImage = find.byKey(
  const ValueKey<String>('agent-chat-host-image-$_id'),
);

void main() {
  testWidgets('an image not on this machine loads through the repository', (
    tester,
  ) async {
    final lifecycle = _Lifecycle();
    await _pump(tester, lifecycle, _attachment());
    expect(_hostImage, findsOneWidget);
    expect(lifecycle.reads, hasLength(1));
    expect(lifecycle.reads.single.$1.chatId, 'chat-1');
    expect(lifecycle.reads.single.$1.workspaceId, 'ws-1');
    expect(lifecycle.reads.single.$2, _id);
  });

  testWidgets('a host without the capability keeps the placeholder', (
    tester,
  ) async {
    final lifecycle = _Lifecycle(supported: false);
    await _pump(tester, lifecycle, _attachment());
    expect(_hostImage, findsNothing);
    expect(find.text('photo.png'), findsOneWidget);
    expect(lifecycle.reads, isEmpty);
  });

  testWidgets('a failed read keeps the placeholder', (tester) async {
    final lifecycle = _Lifecycle(fails: true);
    await _pump(tester, lifecycle, _attachment());
    expect(_hostImage, findsNothing);
    expect(find.text('photo.png'), findsOneWidget);
    expect(lifecycle.reads, hasLength(1));
  });

  testWidgets('an attachment without an upload id is never read', (
    tester,
  ) async {
    final lifecycle = _Lifecycle();
    await _pump(tester, lifecycle, _attachment(attachmentId: null));
    expect(_hostImage, findsNothing);
    expect(find.text('photo.png'), findsOneWidget);
    expect(lifecycle.reads, isEmpty);
  });
}
