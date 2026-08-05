import 'dart:async';

import 'package:alera/src/features/codex_chat/application/codex_chat_controller.dart';
import 'package:alera/src/features/codex_chat/presentation/codex_chat_surface.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

void main() {
  testWidgets('renders rich timeline cells and structured approval controls', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          codexChatRuntimeClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(_SurfaceSettings.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 800,
              child: CodexChatSurface(workspace: _workspace(), tab: _tab()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Answer from Codex'), findsOneWidget);
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Current Codex'), findsOneWidget);
    expect(find.text('Ask First'), findsOneWidget);
    expect(find.byType(GptMarkdown), findsWidgets);
    expect(find.text('dart'), findsOneWidget);
    expect(find.textContaining('void main'), findsOneWidget);
    expect(find.text('Implement Plan'), findsNothing);

    final timeline = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('File changes'),
      200,
      scrollable: timeline,
    );
    await tester.tap(find.text('File changes'));
    await tester.pump();
    expect(find.text('@@ -1 +1 @@'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Allow For Session'),
      200,
      scrollable: timeline,
    );
    expect(find.text('Allow For Session'), findsOneWidget);

    final contextIndicator = find.byWidgetPredicate(
      (widget) => widget is CircularProgressIndicator && widget.value == 0.1,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(contextIndicator));
    await tester.pump();
    expect(find.text('Context Window'), findsOneWidget);
  });
}

Workspace _workspace() {
  final now = DateTime.utc(2026);
  return Workspace(
    id: 'workspace-1',
    projectId: 'project-1',
    name: 'Workspace',
    path: '/repo/workspace',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

WorkspaceTabRecord _tab() {
  final now = DateTime.utc(2026);
  return WorkspaceTabRecord(
    id: 'codex-tab',
    workspaceId: 'workspace-1',
    kind: WorkspaceTabKind.codex,
    title: 'Codex',
    createdAt: now,
    updatedAt: now,
  );
}

final class _SurfaceRuntimeClient implements RuntimeHostClient {
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    if (type == 'codex.thread.open') {
      return <String, Object?>{
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[
            <String, Object?>{
              'id': 'request',
              'kind': 'userMessage',
              'status': 'completed',
              'createdAt': '2026-08-02T11:59:00Z',
              'updatedAt': '2026-08-02T11:59:00Z',
              'markdownText': 'Inspect the workspace',
            },
            <String, Object?>{
              'id': 'answer',
              'kind': 'assistantMessage',
              'status': 'completed',
              'createdAt': '2026-08-02T12:00:00Z',
              'updatedAt': '2026-08-02T12:00:00Z',
              'markdownText':
                  'Answer from Codex\n\n![Malformed](data:not-valid)\n\n```dart\nvoid main() {}\n```',
            },
            <String, Object?>{
              'id': 'reasoning',
              'kind': 'reasoning',
              'status': 'completed',
              'createdAt': '2026-08-02T12:00:00Z',
              'updatedAt': '2026-08-02T12:00:00Z',
              'markdownText': 'Reasoning',
            },
            <String, Object?>{
              'id': 'diff',
              'kind': 'diff',
              'status': 'completed',
              'createdAt': '2026-08-02T12:00:00Z',
              'updatedAt': '2026-08-02T12:00:00Z',
              'title': 'File changes',
              'detailsText': 'diff --git a/a b/a\n@@ -1 +1 @@\n-old\n+new',
            },
            <String, Object?>{
              'id': 'plan',
              'kind': 'plan',
              'status': 'completed',
              'createdAt': '2026-08-02T12:00:00Z',
              'updatedAt': '2026-08-02T12:00:00Z',
              'markdownText': '1. Inspect\n2. Implement',
            },
          ],
          'contextUsed': 1000,
          'contextLimit': 10000,
          'pendingRequests': <Object?>[
            <String, Object?>{
              'id': 1,
              'method': 'item/commandExecution/requestApproval',
              'params': <String, Object?>{
                'command': 'git status',
                'reason': 'Read the workspace',
              },
            },
          ],
        },
      };
    }
    if (type == 'codex.model.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': 'gpt-current',
            'displayName': 'Current Codex',
            'isDefault': true,
          },
        ],
      };
    }
    if (type == 'codex.collaborationModes.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{'mode': 'plan'},
        ],
      };
    }
    return <String, Object?>{'data': const <Object?>[]};
  }

  void dispose() => _events.close();
}

final class _SurfaceSettings extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}
