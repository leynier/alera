part of 'codex_chat_surface_test.dart';

Future<void> _pumpComposerSurface(
  WidgetTester tester,
  _SurfaceRuntimeClient client, {
  WorkspaceFileService? workspaceFiles,
  FakeGitBackend? gitBackend,
  double width = 1000,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        codexChatRuntimeClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(_SurfaceSettings.new),
        if (workspaceFiles != null)
          workspaceFileServiceProvider.overrideWithValue(workspaceFiles),
        if (gitBackend != null)
          gitBackendProvider.overrideWithValue(gitBackend),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: 800,
            child: CodexChatSurface(workspace: _workspace(), tab: _tab()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 30));
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
    this.supportsGoals = false,
    this.goal,
    this.includeGoalInOpenSnapshot = true,
    this.goalGetFailures = 0,
    this.goalGetFailureMessage = 'temporary goal read failure',
    this.goalSetFailures = 0,
    this.goalSetFailureMessage = 'temporary goal set failure',
    this.sessionCommandFailures = const <String>{},
    this.historyNextCursor,
    this.historyTimelineCells = const <Object?>[],
    this.historyGate,
    this.recoveryGate,
    this.pendingRequests,
    this.threadListResponse,
    this.permissionMode,
    this.timelineCells,
    this.activeTurnId,
    this.modelDisplayName = 'Current Codex',
    this.skills = const <String, Object?>{'data': <Object?>[]},
    this.collaborationModes = const <Map<String, Object?>>[
      <String, Object?>{'mode': 'plan'},
    ],
  });

  final Map<String, Object?>? recovery;
  final String approvalMethod;
  final String? activeCwd;
  final bool supportsSessions;
  final bool supportsTurnPolicy;
  final bool supportsGoals;
  Map<String, Object?>? goal;
  final bool includeGoalInOpenSnapshot;
  int goalGetFailures;
  final String goalGetFailureMessage;
  int goalSetFailures;
  final String goalSetFailureMessage;
  final Set<String> sessionCommandFailures;
  final String? historyNextCursor;
  final List<Object?> historyTimelineCells;
  final Completer<void>? historyGate;
  final Completer<void>? recoveryGate;
  final List<Object?>? pendingRequests;
  final Map<String, Object?>? threadListResponse;
  final String? permissionMode;
  final List<Object?>? timelineCells;
  final String? activeTurnId;
  final String modelDisplayName;
  final Map<String, Object?> skills;
  final List<Map<String, Object?>> collaborationModes;
  final List<String> requestTypes = <String>[];
  final List<({String type, Map<String, Object?> payload})> requests =
      <({String type, Map<String, Object?> payload})>[];
  final List<Map<String, Object?>> startTurnPayloads = <Map<String, Object?>>[];
  final List<Map<String, Object?>> responsePayloads = <Map<String, Object?>>[];
  final List<Map<String, Object?>> reviewPayloads = <Map<String, Object?>>[];
  final List<Map<String, Object?>> goalPayloads = <Map<String, Object?>>[];
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
    requests.add((type: type, payload: Map.unmodifiable(payload)));
    if (sessionCommandFailures.contains(type)) {
      throw StateError('$type failed');
    }
    if (type == 'status.get') {
      return <String, Object?>{
        'runtimeCapabilities': <String>[
          if (supportsSessions) aleraRuntimeHostCodexSessionsCapability,
          if (supportsTurnPolicy) aleraRuntimeHostCodexTurnPolicyCapability,
          if (supportsGoals) aleraRuntimeHostCodexGoalsCapability,
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
          if (includeGoalInOpenSnapshot && goal != null) 'goal': goal,
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
                  'markdownText': 'Answer from Codex\n\n![Malformed](data:not-valid)\n\n```dart\nvoid main() {}\n```',
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
          'activeTurnId': activeTurnId,
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
    if (type == 'codex.goal.get') {
      if (goalGetFailures > 0) {
        goalGetFailures -= 1;
        throw StateError(goalGetFailureMessage);
      }
      return <String, Object?>{'goal': goal};
    }
    if (type == 'codex.goal.set') {
      goalPayloads.add(payload);
      if (goalSetFailures > 0) {
        goalSetFailures -= 1;
        throw StateError(goalSetFailureMessage);
      }
      final objective =
          payload['objective']?.toString() ??
          goal?['objective']?.toString() ??
          '';
      final status =
          payload['status']?.toString() ??
          goal?['status']?.toString() ??
          'active';
      goal = <String, Object?>{
        'threadId': 'thread-goal',
        'objective': objective,
        'status': status,
        'tokenBudget': null,
        'tokensUsed': goal?['tokensUsed'] ?? 0,
        'timeUsedSeconds': goal?['timeUsedSeconds'] ?? 0,
        'createdAt': 1,
        'updatedAt': 2,
      };
      return <String, Object?>{'goal': goal};
    }
    if (type == 'codex.goal.clear') {
      goal = null;
      return <String, Object?>{'cleared': true};
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
      await historyGate?.future;
      return <String, Object?>{
        'snapshot': <String, Object?>{
          'timelineCells': historyTimelineCells,
          'pendingRequests': const <Object?>[],
        },
      };
    }
    if (type == 'codex.thread.recover') {
      recoveryRequests += 1;
      if (recoveryRequests == 1) await recoveryGate?.future;
      return <String, Object?>{
        'threadId': null,
        'snapshot': <String, Object?>{
          'timelineCells': const <Object?>[],
          'pendingRequests': const <Object?>[],
        },
      };
    }
    if (type == 'codex.turn.start') {
      startTurnPayloads.add(payload);
      return const <String, Object?>{};
    }
    if (type == 'codex.response') {
      responsePayloads.add(payload);
      return const <String, Object?>{};
    }
    if (type == 'codex.review.start') {
      reviewPayloads.add(payload);
      return const <String, Object?>{};
    }
    if (type == 'codex.model.list') {
      return <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': 'gpt-current',
            'displayName': modelDisplayName,
            'isDefault': true,
            'supportsFastMode': true,
          },
        ],
      };
    }
    if (type == 'codex.collaborationModes.list') {
      return <String, Object?>{'data': collaborationModes};
    }
    if (type == 'codex.skills.list') return skills;
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
  _RecordingWorkspaceFileService({
    this.quickOpenMatches = const <native.WorkspaceQuickOpenMatch>[],
    this.quickOpenSearch,
    this.savedPrompts = const <native.CodexSavedPrompt>[],
  });

  final List<native.WorkspaceQuickOpenMatch> quickOpenMatches;
  final Completer<List<native.WorkspaceQuickOpenMatch>>? quickOpenSearch;
  final List<native.CodexSavedPrompt> savedPrompts;
  String? startedWorkspacePath;
  final List<String> savedPromptWorkspacePaths = <String>[];

  @override
  Future<List<native.CodexSavedPrompt>> listCodexSavedPrompts({
    required String workspacePath,
  }) async {
    savedPromptWorkspacePaths.add(workspacePath);
    return savedPrompts;
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
  }) async => quickOpenSearch?.future ?? quickOpenMatches;

  @override
  Future<void> stopQuickOpenSession({
    required native.WorkspaceQuickOpenSession session,
  }) async {}
}
