import 'dart:async';

import 'package:alera/src/features/codex_chat/application/codex_chat_controller.dart';
import 'package:alera/src/features/codex_chat/application/codex_composer_draft_store.dart';
import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_composer_draft.dart';
import 'package:alera/src/features/codex_chat/presentation/codex_chat_surface.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

part 'codex_chat_surface_session_test_cases.dart';

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
    expect(find.text('Ask For Approval'), findsOneWidget);
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

  testWidgets('keeps history visible while offering rollout recovery', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(
      recovery: const <String, Object?>{
        'kind': 'missingRollout',
        'message': 'The saved Codex context is no longer available.',
      },
    );
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

    expect(find.textContaining('Answer from Codex'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('codex-thread-recovery')),
      findsOneWidget,
    );
    expect(find.text('Continue In New Thread'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('Continue In New Thread'));
    await tester.pump();
    expect(client.recoveryRequests, 1);
  });

  testWidgets('offers cancel turn for legacy approval requests', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(approvalMethod: 'execCommandApproval');
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

    final timeline = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Cancel Turn'),
      200,
      scrollable: timeline,
    );
    expect(find.text('Cancel Turn'), findsOneWidget);
  });

  testWidgets('resolves file mentions from the resumed thread cwd', (
    tester,
  ) async {
    final client = _SurfaceRuntimeClient(activeCwd: '/repo/resumed-workspace');
    final workspaceFiles = _RecordingWorkspaceFileService();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          codexChatRuntimeClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(_SurfaceSettings.new),
          workspaceFileServiceProvider.overrideWithValue(workspaceFiles),
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

    await tester.enterText(find.byType(TextField).last, '@readme');
    await tester.pump(const Duration(milliseconds: 250));

    expect(workspaceFiles.startedWorkspacePath, '/repo/resumed-workspace');
    expect(
      workspaceFiles.savedPromptWorkspacePaths.last,
      '/repo/resumed-workspace',
    );
  });

  registerCodexChatSurfaceSessionTests();
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

WorkspaceTabRecord _tab({
  String id = 'codex-tab',
  String workspaceId = 'workspace-1',
}) {
  final now = DateTime.utc(2026);
  return WorkspaceTabRecord(
    id: id,
    workspaceId: workspaceId,
    kind: WorkspaceTabKind.codex,
    title: 'Codex',
    createdAt: now,
    updatedAt: now,
  );
}

final class _SurfaceRuntimeClient implements RuntimeHostClient {
  _SurfaceRuntimeClient({
    this.recovery,
    this.approvalMethod = 'item/commandExecution/requestApproval',
    this.activeCwd,
    this.supportsSessions = false,
    this.supportsTurnPolicy = true,
    this.historyNextCursor,
    this.pendingRequests,
    this.threadListResponse,
    this.permissionMode,
    this.timelineCells,
  });

  final Map<String, Object?>? recovery;
  final String approvalMethod;
  final String? activeCwd;
  final bool supportsSessions;
  final bool supportsTurnPolicy;
  final String? historyNextCursor;
  final List<Object?>? pendingRequests;
  final Map<String, Object?>? threadListResponse;
  final String? permissionMode;
  final List<Object?>? timelineCells;
  final List<String> requestTypes = <String>[];
  int recoveryRequests = 0;
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
    requestTypes.add(type);
    if (type == 'status.get') {
      return <String, Object?>{
        'runtimeCapabilities': <String>[
          if (supportsSessions) aleraRuntimeHostCodexSessionsCapability,
          if (supportsTurnPolicy) aleraRuntimeHostCodexTurnPolicyCapability,
        ],
      };
    }
    if (type == 'codex.thread.open') {
      return <String, Object?>{
        'threadId': supportsSessions
            ? 'thread-current'
            : recovery == null
            ? null
            : 'thread-recovery',
        'cwd': activeCwd,
        'historyNextCursor': historyNextCursor,
        if (permissionMode != null)
          'configuration': <String, Object?>{
            'selectedModel': 'gpt-current',
            'reasoningEffort': 'medium',
            'speedMode': 'normal',
            'permissionMode': permissionMode,
            'planMode': false,
            'collaborationMode': null,
          },
        'recovery': recovery,
        'snapshot': <String, Object?>{
          'timelineCells':
              timelineCells ??
              <Object?>[
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
          'pendingRequests':
              pendingRequests ??
              <Object?>[
                <String, Object?>{
                  'id': 1,
                  'method': approvalMethod,
                  'params': <String, Object?>{
                    'command': 'git status',
                    'reason': 'Read the workspace',
                  },
                },
              ],
        },
      };
    }
    if (type == 'codex.thread.list') {
      return threadListResponse ?? const <String, Object?>{'data': <Object?>[]};
    }
    if (type == 'codex.thread.resume' ||
        type == 'codex.thread.new' ||
        type == 'codex.thread.clear') {
      return <String, Object?>{
        'threadId': type == 'codex.thread.resume'
            ? 'thread-resumed'
            : 'thread-fresh',
        'cwd': activeCwd ?? '/repo/workspace',
        'snapshot': const <String, Object?>{
          'timelineCells': <Object?>[],
          'pendingRequests': <Object?>[],
        },
      };
    }
    if (type == 'codex.thread.history') {
      return const <String, Object?>{
        'snapshot': <String, Object?>{
          'timelineCells': <Object?>[],
          'pendingRequests': <Object?>[],
        },
      };
    }
    if (type == 'codex.thread.recover') {
      recoveryRequests += 1;
      return <String, Object?>{
        'threadId': null,
        'snapshot': <String, Object?>{
          'timelineCells': const <Object?>[],
          'pendingRequests': const <Object?>[],
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

  void emit(RuntimeHostEvent event) => _events.add(event);
}

final class _SurfaceSettings extends SettingsController {
  @override
  AleraSettings build() => AleraSettings.defaults;
}

final class _RecordingWorkspaceFileService extends WorkspaceFileService {
  String? startedWorkspacePath;
  final List<String> savedPromptWorkspacePaths = <String>[];

  @override
  Future<List<native.CodexSavedPrompt>> listCodexSavedPrompts({
    required String workspacePath,
  }) async {
    savedPromptWorkspacePaths.add(workspacePath);
    return const <native.CodexSavedPrompt>[];
  }

  @override
  Future<native.WorkspaceQuickOpenSession> startQuickOpenSession({
    required String workspacePath,
  }) async {
    startedWorkspacePath = workspacePath;
    return const native.WorkspaceQuickOpenSession(
      id: 'quick-open-session',
      indexedFileCount: 1,
    );
  }

  @override
  Future<List<native.WorkspaceQuickOpenMatch>> searchQuickOpenSession({
    required native.WorkspaceQuickOpenSession session,
    required String query,
    int limit = 50,
  }) async => const <native.WorkspaceQuickOpenMatch>[];

  @override
  Future<void> stopQuickOpenSession({
    required native.WorkspaceQuickOpenSession session,
  }) async {}
}
