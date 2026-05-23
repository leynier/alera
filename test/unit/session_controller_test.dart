import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/domain/chat_message.dart';
import 'package:alera/src/features/projects/domain/chat_summary.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_service.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/domain/composer_draft_item.dart';
import 'package:alera/src/features/session/domain/pending_message.dart';
import 'package:alera/src/features/session/domain/pending_approval.dart';
import 'package:alera/src/features/session/domain/pending_user_input.dart';
import 'package:alera/src/features/session/domain/review_preset_selection.dart';
import 'package:alera/src/features/settings/application/settings_service.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSessionService implements SessionService {
  final StreamController<SessionRuntimeEvent> _eventsController =
      StreamController<SessionRuntimeEvent>.broadcast();
  final Map<String, AleraSession> _sessionsById = <String, AleraSession>{};
  int ensureConnectedCallCount = 0;
  int createSessionCallCount = 0;
  int runInputCallCount = 0;
  SessionCreateRequest? lastCreateSessionRequest;
  String? lastRunInputText;
  String? lastRunInputReasoningEffort;
  String? lastRunInputSpeedMode;
  bool? lastRunInputPlanModeEnabled;
  bool? lastRunInputForceDefaultCollaborationMode;
  List<Map<String, dynamic>> lastRunInputExtraInputItems =
      const <Map<String, dynamic>>[];
  int interruptCallCount = 0;
  String? interruptedSessionId;
  String? interruptedTurnOverride;
  int steerActiveTurnCallCount = 0;
  String? lastSteerSessionId;
  String? lastSteerRawInput;
  String? lastSteerExpectedTurnId;
  int respondUserInputCallCount = 0;
  Object? lastRespondUserInputRequestId;
  Map<String, dynamic>? lastRespondUserInputAnswers;
  CodexReviewTarget? lastReviewTarget;
  Duration runInputDelay = Duration.zero;
  Future<void> Function()? onRunInputBeforeComplete;
  Future<void> Function(String sessionId)? onSetActiveSessionBeforeComplete;

  @override
  Stream<SessionRuntimeEvent> get events => _eventsController.stream;

  void emitEvent(SessionRuntimeEvent event) {
    _eventsController.add(event);
  }

  @override
  List<AleraSession> get sessions {
    final list = _sessionsById.values.toList(growable: false);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<AleraSession> createSession(SessionCreateRequest request) async {
    createSessionCallCount += 1;
    lastCreateSessionRequest = request;
    final now = DateTime.now().toUtc();
    final id = 'session-$createSessionCallCount';
    final session = AleraSession(
      id: id,
      request: request,
      workspacePath: request.projectPath,
      createdAt: now,
      updatedAt: now,
      title: 'session',
      model: request.model,
      threadId: 'thread-1',
      projectId: request.projectId,
      worktreeId: request.worktreeId,
    );
    _sessionsById[session.id] = session;
    return session;
  }

  @override
  Future<void> ensureConnected() async {
    ensureConnectedCallCount += 1;
  }

  @override
  AleraSession? findLatestSessionForWorkspace(String workspacePath) {
    for (final session in _sessionsById.values) {
      if (session.workspacePath == workspacePath) {
        return session;
      }
    }
    return null;
  }

  @override
  Future<void> interruptActiveTurn({
    required String sessionId,
    String? turnIdOverride,
  }) async {
    interruptCallCount += 1;
    interruptedSessionId = sessionId;
    interruptedTurnOverride = turnIdOverride;
  }

  @override
  Future<void> compactContext({required String sessionId}) async {}

  @override
  Future<String> steerActiveTurn({
    required String sessionId,
    required String rawInput,
    required String expectedTurnId,
    List<Map<String, dynamic>> extraInputItems = const <Map<String, dynamic>>[],
  }) async {
    steerActiveTurnCallCount += 1;
    lastSteerSessionId = sessionId;
    lastSteerRawInput = rawInput;
    lastSteerExpectedTurnId = expectedTurnId;
    return expectedTurnId;
  }

  @override
  Future<void> approveRequest(
    Object requestId, {
    bool forSession = false,
  }) async {}

  @override
  Future<void> declineRequest(Object requestId) async {}

  @override
  Future<void> respondUserInput(
    Object requestId,
    Map<String, dynamic> answers,
  ) async {
    respondUserInputCallCount += 1;
    lastRespondUserInputRequestId = requestId;
    lastRespondUserInputAnswers = answers;
  }

  @override
  Future<void> runInput({
    required String sessionId,
    required String rawInput,
    required String reasoningEffort,
    required String speedMode,
    List<Map<String, dynamic>> extraInputItems = const <Map<String, dynamic>>[],
    bool planModeEnabled = false,
    bool forceDefaultCollaborationMode = false,
    String approvalPolicy = 'never',
  }) async {
    runInputCallCount += 1;
    lastRunInputText = rawInput;
    lastRunInputReasoningEffort = reasoningEffort;
    lastRunInputSpeedMode = speedMode;
    lastRunInputPlanModeEnabled = planModeEnabled;
    lastRunInputForceDefaultCollaborationMode = forceDefaultCollaborationMode;
    lastRunInputExtraInputItems = List<Map<String, dynamic>>.of(
      extraInputItems,
    );
    final turnId = 'turn-$runInputCallCount';
    final existing = _sessionsById[sessionId];
    if (existing == null) {
      throw StateError('session not found');
    }
    _sessionsById[sessionId] = existing.copyWith(
      lastTurnId: turnId,
      updatedAt: DateTime.now().toUtc(),
    );
    if (onRunInputBeforeComplete != null) {
      await onRunInputBeforeComplete!.call();
    }
    if (runInputDelay > Duration.zero) {
      await Future<void>.delayed(runInputDelay);
    }
  }

  @override
  Future<void> renameSessionThread({
    required String sessionId,
    required String name,
  }) async {
    final existing = _sessionsById[sessionId];
    if (existing == null) {
      throw StateError('session not found');
    }
    _sessionsById[sessionId] = existing.copyWith(
      title: name,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> renameThread({required String sessionId, required String name}) {
    return renameSessionThread(sessionId: sessionId, name: name);
  }

  @override
  Future<CodexReviewStartResult> startReview({
    required String sessionId,
    required CodexReviewTarget target,
    CodexReviewDelivery? delivery,
  }) async {
    lastReviewTarget = target;
    final existing = _sessionsById[sessionId];
    if (existing == null) {
      throw StateError('session not found');
    }
    final reviewThreadId = delivery == CodexReviewDelivery.detached
        ? '${existing.threadId}-review'
        : existing.threadId!;
    final turnId = 'review-turn-$runInputCallCount';
    _sessionsById[sessionId] = existing.copyWith(
      lastTurnId: reviewThreadId == existing.threadId
          ? turnId
          : existing.lastTurnId,
      updatedAt: DateTime.now().toUtc(),
    );
    return CodexReviewStartResult(
      turn: CodexTurnSummary(id: turnId, status: 'inProgress'),
      reviewThreadId: reviewThreadId,
    );
  }

  @override
  Future<List<CodexCollaborationModePreset>> listCollaborationModes() async {
    return const <CodexCollaborationModePreset>[
      CodexCollaborationModePreset(
        name: 'default',
        kind: CodexCollaborationModeKind.defaultMode,
        model: 'gpt-5.2-codex',
      ),
    ];
  }

  @override
  Future<List<CodexSkillsListEntry>> listSkills({
    List<String>? cwds,
    bool forceReload = false,
    List<CodexSkillsListExtraRootsForCwd>? perCwdExtraUserRoots,
  }) async {
    return <CodexSkillsListEntry>[
      CodexSkillsListEntry(
        cwd: (cwds == null || cwds.isEmpty) ? '/tmp/project' : cwds.first,
        skills: const <CodexSkillMetadata>[
          CodexSkillMetadata(
            name: 'fake-skill',
            description: 'Fake skill',
            path: '/tmp/project/.codex/skills/fake/SKILL.md',
            scope: 'repo',
            enabled: true,
          ),
        ],
        errors: const <CodexSkillErrorInfo>[],
      ),
    ];
  }

  @override
  Future<CodexAppsPage> listApps({
    String? sessionId,
    String? cursor,
    int? limit,
    bool forceRefetch = false,
  }) async {
    return const CodexAppsPage(
      data: <CodexAppInfo>[
        CodexAppInfo(
          id: 'demo-app',
          name: 'Demo App',
          isAccessible: true,
          isEnabled: true,
          pluginDisplayNames: <String>[],
        ),
      ],
      nextCursor: null,
    );
  }

  @override
  Future<AleraSession> setActiveSession(String sessionId) async {
    final existing = _sessionsById[sessionId];
    if (existing == null) {
      throw StateError('session not found');
    }
    if (onSetActiveSessionBeforeComplete != null) {
      await onSetActiveSessionBeforeComplete!.call(sessionId);
    }
    return existing;
  }

  @override
  Future<void> shutdown() async {
    await _eventsController.close();
  }

  @override
  AleraSession? findSessionById(String sessionId) => _sessionsById[sessionId];

  @override
  void adoptPersistedSession(AleraSession session) {
    _sessionsById[session.id] = session;
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    _sessionsById.remove(sessionId);
  }

  @override
  Future<void> persistMessage({
    required String sessionId,
    required ChatMessageRole role,
    required String text,
    String? toolCallsJson,
    int? tokensIn,
    int? tokensOut,
    double? costUsd,
    String? turnId,
  }) async {
    final existing = _persistedMessages[sessionId] ?? const <ChatMessage>[];
    _persistedMessages[sessionId] = List<ChatMessage>.unmodifiable([
      ...existing,
      ChatMessage(
        chatId: sessionId,
        seq: existing.length,
        role: role,
        text: text,
        toolCallsJson: toolCallsJson,
        tokensIn: tokensIn,
        tokensOut: tokensOut,
        costUsd: costUsd,
        turnId: turnId,
        createdAt: DateTime.now().toUtc(),
      ),
    ]);
  }

  List<ChatMessage> persistedMessagesFor(String chatId) =>
      _persistedMessages[chatId] ?? const <ChatMessage>[];

  void seedPersistedMessages(String chatId, List<ChatMessage> messages) {
    _persistedMessages[chatId] = List<ChatMessage>.unmodifiable(messages);
  }

  final Map<String, List<ChatMessage>> _persistedMessages =
      <String, List<ChatMessage>>{};

  @override
  Future<List<ChatMessage>> loadPersistedMessages(String chatId) async {
    return persistedMessagesFor(chatId);
  }

  final Map<String, List<TimelineCell>> _persistedCells =
      <String, List<TimelineCell>>{};

  void seedPersistedCells(String chatId, List<TimelineCell> cells) {
    _persistedCells[chatId] = List<TimelineCell>.unmodifiable(cells);
  }

  List<TimelineCell> persistedCellsFor(String chatId) =>
      _persistedCells[chatId] ?? const <TimelineCell>[];

  @override
  Future<List<TimelineCell>> loadPersistedCells(String chatId) async {
    return persistedCellsFor(chatId);
  }

  @override
  Future<void> persistTimelineCells({
    required String sessionId,
    required List<TimelineCell> cells,
  }) async {
    _persistedCells[sessionId] = List<TimelineCell>.unmodifiable(cells);
  }

  @override
  int runningTurnCountFor(String sessionId) => 0;

  @override
  String? activeTurnIdFor(String sessionId) => null;

  @override
  Future<void> updateSessionModel({
    required String sessionId,
    required String modelId,
  }) async {
    final existing = _sessionsById[sessionId];
    if (existing == null) {
      throw StateError('session not found');
    }
    _sessionsById[sessionId] = existing.copyWith(
      model: modelId,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  void emitNotification(String method, Map<String, dynamic> params) {
    final turn = params['turn'];
    if (turn is Map<String, dynamic>) {
      final turnId = turn['id']?.toString();
      final threadId = turn['threadId']?.toString();
      if (turnId != null && threadId != null) {
        for (final entry in _sessionsById.entries) {
          if (entry.value.threadId == threadId) {
            _sessionsById[entry.key] = entry.value.copyWith(
              lastTurnId: turnId,
              updatedAt: DateTime.now().toUtc(),
            );
          }
        }
      }
    }
    _eventsController.add(
      SessionNotificationEvent(
        method: method,
        payload: <String, dynamic>{'params': params},
      ),
    );
  }

  void emitRuntimeEvent(SessionRuntimeEvent event) {
    _eventsController.add(event);
  }
}

class _FakeProjectService implements ProjectService {
  @override
  Future<bool> isGitRepository(String path) async => true;

  @override
  Future<ProjectValidationResult> validateGitRepository(String path) async {
    return ProjectValidationResult.ok();
  }

  @override
  Future<List<String>> listGitBranches(String path) async {
    return const <String>['main', 'origin/main', 'feature/demo'];
  }
}

class _FakeSettingsService implements SettingsService {
  _FakeSettingsService(
    this._selectedModel,
    this._selectedReasoningEffort,
    this._markdownEnabled, {
    this._selectedSpeedMode = 'normal',
    this._planModeEnabled = false,
    this._permissionMode = PermissionMode.defaultMode,
  });

  String _selectedModel;
  String _selectedReasoningEffort;
  String _selectedSpeedMode;
  bool _markdownEnabled;
  bool _planModeEnabled;
  PermissionMode _permissionMode;
  int saveCallCount = 0;

  @override
  Future<SettingsSnapshot> load() async {
    return SettingsSnapshot(
      selectedModel: _selectedModel,
      selectedReasoningEffort: _selectedReasoningEffort,
      selectedSpeedMode: _selectedSpeedMode,
      markdownEnabled: _markdownEnabled,
      planModeEnabled: _planModeEnabled,
      permissionMode: _permissionMode,
    );
  }

  @override
  Future<void> save(SettingsSnapshot snapshot) async {
    saveCallCount += 1;
    _selectedModel = snapshot.selectedModel;
    _selectedReasoningEffort = snapshot.selectedReasoningEffort;
    _selectedSpeedMode = snapshot.selectedSpeedMode;
    _markdownEnabled = snapshot.markdownEnabled;
    _planModeEnabled = snapshot.planModeEnabled;
    _permissionMode = snapshot.permissionMode;
  }

  String get selectedModel => _selectedModel;
  String get selectedReasoningEffort => _selectedReasoningEffort;
  String get selectedSpeedMode => _selectedSpeedMode;
  bool get markdownEnabled => _markdownEnabled;
  bool get planModeEnabled => _planModeEnabled;
  PermissionMode get permissionMode => _permissionMode;
}

void main() {
  group('session controller', () {
    test('selectWorkspace without existing session boots connection', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.3-codex', 'high', true);
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      final ok = await controller.selectWorkspaceFromPath('/repo');

      expect(ok, isTrue);
      expect(fakeService.ensureConnectedCallCount, 1);
      expect(controller.state.activeSessionId, isNull);
      expect(
        controller.state.connectionState,
        AppServerConnectionState.connected,
      );
      expect(controller.state.selectedWorkspacePath, isNotNull);
      expect(controller.state.preSessionModelId, 'gpt-5.3-codex');
      expect(controller.state.preSessionReasoningEffort, 'high');
      expect(controller.state.activeMarkdownEnabled, isTrue);
    });

    test('bootstrap restores plan and permission from settings', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService(
        'gpt-5.3-codex',
        'high',
        true,
        planModeEnabled: true,
        permissionMode: PermissionMode.fullAccess,
      );
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();

      expect(controller.state.planModeEnabled, isTrue);
      expect(controller.state.permissionMode, PermissionMode.fullAccess);
    });

    test('sendInput lazily creates session on first prompt', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.3-codex', 'high', true);
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      await controller.selectWorkspaceFromPath('/repo');

      expect(controller.state.activeSessionId, isNull);

      await controller.sendInput('Hello from first prompt');

      expect(fakeService.createSessionCallCount, 1);
      expect(fakeService.runInputCallCount, 1);
      expect(fakeService.lastRunInputText, 'Hello from first prompt');
      expect(
        fakeService.lastCreateSessionRequest?.firstPrompt,
        'Hello from first prompt',
      );
      expect(fakeService.lastCreateSessionRequest?.projectPath, '/repo');
      expect(fakeService.lastCreateSessionRequest?.model, 'gpt-5.3-codex');
      expect(fakeService.lastRunInputReasoningEffort, 'high');
      expect(controller.state.activeSessionId, isNotNull);
      expect(controller.state.activeSession, isNotNull);
      expect(
        fakeService.persistedMessagesFor(controller.state.activeSessionId!),
        hasLength(1),
      );
      expect(
        fakeService
            .persistedMessagesFor(controller.state.activeSessionId!)
            .single
            .text,
        'Hello from first prompt',
      );
      expect(
        controller.state.connectionState,
        AppServerConnectionState.connected,
      );
    });

    test(
      'slash command first input preserves pending project context',
      () async {
        final fakeService = _FakeSessionService();
        final fakeSettings = _FakeSettingsService(
          'gpt-5.3-codex',
          'high',
          true,
        );
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: fakeSettings,
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        final now = DateTime.utc(2026, 5, 10, 12);
        final project = Project(
          id: 'project-review',
          name: 'alera',
          repoPath: '/repo',
          createdAt: now,
          updatedAt: now,
        );

        await controller.activateChatStub(project: project);
        await controller.sendInput('/review');

        expect(fakeService.createSessionCallCount, 1);
        expect(
          fakeService.lastReviewTarget,
          isA<CodexReviewUncommittedChangesTarget>(),
        );
        expect(fakeService.lastCreateSessionRequest?.firstPrompt, '/review');
        expect(fakeService.lastCreateSessionRequest?.projectPath, '/repo');
        expect(fakeService.lastCreateSessionRequest?.projectId, project.id);
        expect(fakeService.lastCreateSessionRequest?.worktreeId, isNull);
      },
    );

    test(
      'updateActiveSessionModel without session updates draft and settings',
      () async {
        final fakeService = _FakeSessionService();
        final fakeSettings = _FakeSettingsService(
          'gpt-5.3-codex',
          'high',
          true,
        );
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: fakeSettings,
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.updateActiveSessionModel('gpt-5.2-codex');

        expect(controller.state.activeSessionId, isNull);
        expect(controller.state.preSessionModelId, 'gpt-5.2-codex');
        expect(fakeSettings.selectedModel, 'gpt-5.2-codex');
        expect(fakeSettings.selectedReasoningEffort, 'high');
        expect(fakeSettings.saveCallCount, greaterThan(0));
      },
    );

    test(
      'updateActiveSessionModel auto-adjusts unsupported reasoning effort for mini',
      () async {
        final fakeService = _FakeSessionService();
        final fakeSettings = _FakeSettingsService(
          'gpt-5.3-codex',
          'xhigh',
          true,
        );
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: fakeSettings,
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.updateActiveSessionModel('gpt-5.1-codex-mini');

        expect(controller.state.preSessionModelId, 'gpt-5.1-codex-mini');
        expect(controller.state.activeReasoningEffort, 'high');
        expect(fakeSettings.selectedModel, 'gpt-5.1-codex-mini');
        expect(fakeSettings.selectedReasoningEffort, 'high');
      },
    );

    test('updateReasoningEffort persists selected effort', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.3-codex', 'high', true);
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      await controller.updateReasoningEffort('low');

      expect(controller.state.activeReasoningEffort, 'low');
      expect(fakeSettings.selectedReasoningEffort, 'low');
      expect(fakeSettings.selectedModel, 'gpt-5.3-codex');
    });

    test('togglePlanMode persists plan mode to settings', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService(
        'gpt-5.3-codex',
        'high',
        true,
        planModeEnabled: false,
      );
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      expect(controller.state.planModeEnabled, isFalse);

      controller.togglePlanMode();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.planModeEnabled, isTrue);
      expect(fakeSettings.planModeEnabled, isTrue);
    });

    test('setPermissionMode persists approval mode to settings', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.3-codex', 'high', true);
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      expect(controller.state.permissionMode, PermissionMode.defaultMode);

      controller.setPermissionMode(PermissionMode.fullAccess);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.permissionMode, PermissionMode.fullAccess);
      expect(fakeSettings.permissionMode, PermissionMode.fullAccess);
    });

    test('updateSpeedMode persists fast for supported models', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.5', 'high', true);
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      await controller.updateSpeedMode('fast');

      expect(controller.state.activeSpeedMode, 'fast');
      expect(fakeSettings.selectedSpeedMode, 'fast');
    });

    test(
      'updateActiveSessionModel downgrades fast for unsupported models',
      () async {
        final fakeService = _FakeSessionService();
        final fakeSettings = _FakeSettingsService(
          'gpt-5.5',
          'high',
          true,
          selectedSpeedMode: 'fast',
        );
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: fakeSettings,
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        expect(controller.state.activeSpeedMode, 'fast');

        await controller.updateActiveSessionModel('gpt-5.3-codex');

        expect(controller.state.activeSpeedMode, 'normal');
        expect(fakeSettings.selectedSpeedMode, 'normal');
      },
    );

    test('updateMarkdownEnabled persists selected markdown mode', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.3-codex', 'high', true);
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      await controller.updateMarkdownEnabled(false);

      expect(controller.state.activeMarkdownEnabled, isFalse);
      expect(fakeSettings.markdownEnabled, isFalse);
      expect(fakeSettings.selectedModel, 'gpt-5.3-codex');
      expect(fakeSettings.selectedReasoningEffort, 'high');
    });

    test(
      'interruptActiveTurn toggles state and clears on turn completion',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.createSession(
          const SessionCreateRequest(
            projectPath: '/repo',
            firstPrompt: 'hello',
            model: 'gpt-5.3-codex',
          ),
        );

        fakeService.emitNotification('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'inProgress',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(controller.state.runningTurnCount, 1);

        await controller.interruptActiveTurn();
        expect(controller.state.isInterrupting, isTrue);
        expect(fakeService.interruptCallCount, 1);
        expect(
          fakeService.interruptedSessionId,
          controller.state.activeSessionId,
        );

        fakeService.emitNotification('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'interrupted',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.isInterrupting, isFalse);
        expect(controller.state.runningTurnCount, 0);
      },
    );

    test('background waiting status is reflected and then cleared', () async {
      final fakeService = _FakeSessionService();
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      await controller.createSession(
        const SessionCreateRequest(
          projectPath: '/repo',
          firstPrompt: 'hello',
          model: 'gpt-5.3-codex',
        ),
      );

      fakeService.emitNotification('turn/started', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn-1',
          'threadId': 'thread-1',
          'status': 'inProgress',
        },
      });
      fakeService.emitNotification('background/event', <String, dynamic>{
        'kind': 'background_terminal_waiting',
        'message': 'waiting for background terminal',
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state.statusHeader, 'Waiting for background terminal');

      fakeService.emitNotification('turn/completed', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn-1',
          'threadId': 'thread-1',
          'status': 'completed',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.statusHeader, isNull);
    });

    test(
      'user input request is accepted when threadId matches active session',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.createSession(
          const SessionCreateRequest(
            projectPath: '/repo',
            firstPrompt: 'hello',
            model: 'gpt-5.3-codex',
          ),
        );

        fakeService.emitRuntimeEvent(
          const SessionUserInputRequestEvent(
            requestId: 1001,
            threadId: 'thread-1',
            turnId: 'turn-x',
            itemId: 'item-x',
            questions: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'implement_now',
                'header': 'Implement',
                'question': 'Implement this plan?',
                'options': <Map<String, dynamic>>[
                  <String, dynamic>{'label': 'yes', 'description': 'Proceed'},
                ],
              },
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNotNull);
        expect(
          controller.state.pendingUserInput?.questions.first.id,
          'implement_now',
        );
      },
    );

    test(
      'user input request is dropped when explicit threadId mismatches',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.createSession(
          const SessionCreateRequest(
            projectPath: '/repo',
            firstPrompt: 'hello',
            model: 'gpt-5.3-codex',
          ),
        );

        fakeService.emitRuntimeEvent(
          const SessionUserInputRequestEvent(
            requestId: 1002,
            threadId: 'thread-other',
            turnId: 'turn-x',
            itemId: 'item-x',
            questions: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'implement_now',
                'header': 'Implement',
                'question': 'Implement this plan?',
              },
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNull);
      },
    );

    test(
      'user input request falls back to turnId when threadId is absent',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.createSession(
          const SessionCreateRequest(
            projectPath: '/repo',
            firstPrompt: 'hello',
            model: 'gpt-5.3-codex',
          ),
        );
        fakeService.emitNotification('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'inProgress',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        fakeService.emitRuntimeEvent(
          const SessionUserInputRequestEvent(
            requestId: 1003,
            threadId: null,
            turnId: 'turn-1',
            itemId: 'item-x',
            questions: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'implement_now',
                'header': 'Implement',
                'question': 'Implement this plan?',
              },
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(controller.state.pendingUserInput, isNotNull);

        controller.dismissUserInput();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        fakeService.emitNotification('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-2',
            'threadId': 'thread-1',
            'status': 'inProgress',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        fakeService.emitRuntimeEvent(
          const SessionUserInputRequestEvent(
            requestId: 1004,
            threadId: '   ',
            turnId: 'turn-2',
            itemId: 'item-y',
            questions: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'implement_now',
                'header': 'Implement',
                'question': 'Implement this plan?',
              },
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(controller.state.pendingUserInput, isNotNull);

        controller.dismissUserInput();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        fakeService.emitRuntimeEvent(
          const SessionUserInputRequestEvent(
            requestId: 1005,
            threadId: null,
            turnId: 'turn-other',
            itemId: 'item-z',
            questions: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'implement_now',
                'header': 'Implement',
                'question': 'Implement this plan?',
              },
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(controller.state.pendingUserInput, isNull);
      },
    );

    test(
      'user input request with empty questions auto-responds and logs',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.createSession(
          const SessionCreateRequest(
            projectPath: '/repo',
            firstPrompt: 'hello',
            model: 'gpt-5.3-codex',
          ),
        );

        fakeService.emitRuntimeEvent(
          const SessionUserInputRequestEvent(
            requestId: 1006,
            threadId: 'thread-1',
            turnId: 'turn-1',
            itemId: 'item-empty',
            questions: <Map<String, dynamic>>[],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNull);
        expect(fakeService.respondUserInputCallCount, greaterThan(0));
        expect(fakeService.lastRespondUserInputRequestId, 1006);
        expect(fakeService.lastRespondUserInputAnswers, isEmpty);
        expect(
          controller.state.activityLog.any(
            (line) => line.contains('invalid -> auto-answered'),
          ),
          isTrue,
        );
      },
    );

    test(
      'invalid backend user input request does not block local plan fallback',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        await controller.sendInput('build a plan');

        fakeService.emitNotification('item/plan/delta', <String, dynamic>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'turn-1-plan',
          'delta': 'step 1',
        });
        fakeService.emitRuntimeEvent(
          const SessionUserInputRequestEvent(
            requestId: 1201,
            threadId: 'thread-1',
            turnId: 'turn-1',
            itemId: 'item-invalid',
            questions: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'implement_now',
                'header': 'Implementation',
              },
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNull);
        expect(fakeService.respondUserInputCallCount, 1);
        expect(fakeService.lastRespondUserInputRequestId, 1201);
        expect(fakeService.lastRespondUserInputAnswers, isEmpty);

        fakeService.emitNotification('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNotNull);
        expect(
          controller.state.pendingUserInput?.source,
          PendingUserInputSource.localPlanFallback,
        );
        expect(
          controller.state.activityLog.any(
            (line) =>
                line.contains('runtime/planFallback gate') &&
                line.contains('turnId=turn-1') &&
                line.contains('hasBackendRequest=false'),
          ),
          isTrue,
        );
      },
    );

    test('user input request supports question schema aliases', () async {
      final fakeService = _FakeSessionService();
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      await controller.createSession(
        const SessionCreateRequest(
          projectPath: '/repo',
          firstPrompt: 'hello',
          model: 'gpt-5.3-codex',
        ),
      );

      fakeService.emitRuntimeEvent(
        const SessionUserInputRequestEvent(
          requestId: 1202,
          threadId: 'thread-1',
          turnId: 'turn-alias',
          itemId: 'item-alias',
          questions: <Map<String, dynamic>>[
            <String, dynamic>{
              'questionId': 'implement_alias',
              'title': 'Implementation',
              'prompt': 'Implement this plan?',
              'isOther': true,
              'other_label': 'No, and tell Alera what to do differently',
              'choices': <Map<String, dynamic>>[
                <String, dynamic>{
                  'value': 'Yes, implement this plan',
                  'hint': 'Proceed with implementation',
                },
              ],
            },
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final pending = controller.state.pendingUserInput;
      expect(pending, isNotNull);
      expect(pending?.source, PendingUserInputSource.backend);
      expect(pending?.questions.single.id, 'implement_alias');
      expect(pending?.questions.single.header, 'Implementation');
      expect(pending?.questions.single.question, 'Implement this plan?');
      expect(
        pending?.questions.single.otherLabel,
        'No, and tell Alera what to do differently',
      );
      expect(
        pending?.questions.single.options?.single.label,
        'Yes, implement this plan',
      );
      expect(
        pending?.questions.single.options?.single.description,
        'Proceed with implementation',
      );
      expect(fakeService.respondUserInputCallCount, 0);
      expect(
        controller.state.activityLog.any(
          (line) =>
              line.contains('runtime/requestUserInput parsed') &&
              line.contains('turnId=turn-alias') &&
              line.contains('usedAliases=true'),
        ),
        isTrue,
      );
    });

    test(
      'valid backend user input request still suppresses local plan fallback',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        await controller.sendInput('build a plan');

        fakeService.emitNotification('item/plan/delta', <String, dynamic>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'turn-1-plan',
          'delta': 'step 1',
        });
        fakeService.emitRuntimeEvent(
          const SessionUserInputRequestEvent(
            requestId: 1203,
            threadId: 'thread-1',
            turnId: 'turn-1',
            itemId: 'item-valid',
            questions: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'implement_now',
                'header': 'Implement',
                'question': 'Implement this plan?',
              },
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        fakeService.emitNotification('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final pending = controller.state.pendingUserInput;
        expect(pending, isNotNull);
        expect(pending?.source, PendingUserInputSource.backend);
        expect(pending?.questions.single.id, 'implement_now');
        expect(pending?.localPlanTurnId, isNull);
        expect(fakeService.respondUserInputCallCount, 0);
      },
    );

    test(
      'backend request seen without pending card for same turn does not block local fallback',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        await controller.sendInput('build a plan');

        fakeService.emitNotification('item/plan/delta', <String, dynamic>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'turn-1-plan',
          'delta': 'step 1',
        });

        fakeService.emitRuntimeEvent(
          const SessionUserInputRequestEvent(
            requestId: 1204,
            threadId: 'thread-1',
            turnId: 'turn-1',
            itemId: 'item-turn-1',
            questions: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'implement_now',
                'header': 'Implement',
                'question': 'Implement this plan?',
              },
            ],
          ),
        );
        fakeService.emitRuntimeEvent(
          const SessionUserInputRequestEvent(
            requestId: 1205,
            threadId: 'thread-1',
            turnId: 'turn-2',
            itemId: 'item-turn-2',
            questions: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'implement_now',
                'header': 'Implement',
                'question': 'Implement this plan?',
              },
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNotNull);
        expect(
          controller.state.pendingUserInput?.source,
          PendingUserInputSource.backend,
        );
        expect(controller.state.pendingUserInput?.turnId, 'turn-2');

        fakeService.emitNotification('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNotNull);
        expect(
          controller.state.pendingUserInput?.source,
          PendingUserInputSource.localPlanFallback,
        );
        expect(controller.state.pendingUserInput?.localPlanTurnId, 'turn-1');
        expect(
          controller.state.activityLog.any(
            (line) =>
                line.contains(
                  'runtime/planFallback backendRequestWithoutPending',
                ) &&
                line.contains('turnId=turn-1'),
          ),
          isTrue,
        );
      },
    );

    test(
      'backend dismiss marks turn as resolved and prevents local fallback',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        await controller.sendInput('build a plan');

        fakeService.emitNotification('item/plan/delta', <String, dynamic>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'turn-1-plan',
          'delta': 'step 1',
        });
        fakeService.emitRuntimeEvent(
          const SessionUserInputRequestEvent(
            requestId: 1206,
            threadId: 'thread-1',
            turnId: 'turn-1',
            itemId: 'item-valid',
            questions: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'implement_now',
                'header': 'Implement',
                'question': 'Implement this plan?',
              },
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        controller.dismissUserInput();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNull);
        expect(fakeService.respondUserInputCallCount, 1);
        expect(fakeService.lastRespondUserInputRequestId, 1206);
        expect(fakeService.lastRespondUserInputAnswers, isEmpty);

        fakeService.emitNotification('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNull);
        expect(
          controller.state.activityLog.any(
            (line) => line.contains('runtime/planFallback shown turnId=turn-1'),
          ),
          isFalse,
        );
      },
    );

    test(
      'backend submit marks turn as resolved and prevents local fallback',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        await controller.sendInput('build a plan');

        fakeService.emitNotification('item/plan/delta', <String, dynamic>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'turn-1-plan',
          'delta': 'step 1',
        });
        fakeService.emitRuntimeEvent(
          const SessionUserInputRequestEvent(
            requestId: 1207,
            threadId: 'thread-1',
            turnId: 'turn-1',
            itemId: 'item-valid',
            questions: <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'implement_now',
                'header': 'Implement',
                'question': 'Implement this plan?',
              },
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await controller.submitUserInput(<String, dynamic>{
          'implement_now': <String, dynamic>{
            'answers': <String>['Yes, implement this plan'],
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNull);
        expect(fakeService.respondUserInputCallCount, 1);
        expect(fakeService.lastRespondUserInputRequestId, 1207);
        expect(fakeService.lastRespondUserInputAnswers, <String, dynamic>{
          'implement_now': <String, dynamic>{
            'answers': <String>['Yes, implement this plan'],
          },
        });

        fakeService.emitNotification('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNull);
        expect(
          controller.state.activityLog.any(
            (line) => line.contains('runtime/planFallback shown turnId=turn-1'),
          ),
          isFalse,
        );
      },
    );

    test('backend empty submit is ignored and does not resolve turn', () async {
      final fakeService = _FakeSessionService();
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      await controller.selectWorkspaceFromPath('/repo');
      controller.togglePlanMode();
      await controller.sendInput('build a plan');

      fakeService.emitNotification('item/plan/delta', <String, dynamic>{
        'threadId': 'thread-1',
        'turnId': 'turn-1',
        'itemId': 'turn-1-plan',
        'delta': 'step 1',
      });
      fakeService.emitRuntimeEvent(
        const SessionUserInputRequestEvent(
          requestId: 1208,
          threadId: 'thread-1',
          turnId: 'turn-1',
          itemId: 'item-valid',
          questions: <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'implement_now',
              'header': 'Implement',
              'question': 'Implement this plan?',
            },
          ],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await controller.submitUserInput(const <String, dynamic>{});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.pendingUserInput, isNotNull);
      expect(
        controller.state.pendingUserInput?.source,
        PendingUserInputSource.backend,
      );
      expect(fakeService.respondUserInputCallCount, 0);
      expect(
        controller.state.activityLog.any(
          (line) =>
              line.contains('runtime/userInput submitIgnored empty') &&
              line.contains('source=backend') &&
              line.contains('turnId=turn-1'),
        ),
        isTrue,
      );

      fakeService.emitNotification('turn/completed', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn-1',
          'threadId': 'thread-1',
          'status': 'completed',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.pendingUserInput, isNotNull);
      expect(
        controller.state.pendingUserInput?.source,
        PendingUserInputSource.backend,
      );
      expect(
        controller.state.activityLog.any(
          (line) =>
              line.contains('runtime/planFallback gate') &&
              line.contains('turnId=turn-1') &&
              line.contains('resolved=false'),
        ),
        isTrue,
      );
    });

    test(
      'local plan fallback appears when plan turn completes without backend request',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        await controller.sendInput('build a plan');

        fakeService.emitNotification('item/plan/delta', <String, dynamic>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'turn-1-plan',
          'delta': 'step 1',
        });
        fakeService.emitNotification('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final pending = controller.state.pendingUserInput;
        expect(pending, isNotNull);
        expect(pending?.source, PendingUserInputSource.localPlanFallback);
        expect(pending?.localPlanTurnId, 'turn-1');
        expect(pending?.questions.single.question, 'Implement this plan?');
        expect(
          pending?.questions.single.otherLabel,
          'No, and tell Alera what to do differently',
        );
      },
    );

    test(
      'local plan fallback appears when turn completes before runInput returns',
      () async {
        final fakeService = _FakeSessionService();
        fakeService.runInputDelay = const Duration(milliseconds: 30);
        fakeService.onRunInputBeforeComplete = () async {
          fakeService.emitNotification('item/plan/delta', <String, dynamic>{
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'turn-1-plan',
            'delta': 'step 1',
          });
          fakeService.emitNotification('turn/completed', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-1',
              'threadId': 'thread-1',
              'status': 'completed',
            },
          });
        };
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        await controller.sendInput('build a plan');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final pending = controller.state.pendingUserInput;
        expect(pending, isNotNull);
        expect(pending?.source, PendingUserInputSource.localPlanFallback);
        expect(
          controller.state.activityLog.any(
            (line) => line.contains('awaiting late arm turnId=turn-1'),
          ),
          isTrue,
        );
      },
    );

    test(
      'local plan fallback appears when backend submit resolves before runInput returns',
      () async {
        final fakeService = _FakeSessionService();
        late SessionController controller;
        fakeService.runInputDelay = const Duration(milliseconds: 30);
        fakeService.onRunInputBeforeComplete = () async {
          fakeService.emitNotification('item/plan/delta', <String, dynamic>{
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'turn-1-plan',
            'delta': 'step 1',
          });
          fakeService.emitRuntimeEvent(
            const SessionUserInputRequestEvent(
              requestId: 1209,
              threadId: 'thread-1',
              turnId: 'turn-1',
              itemId: 'item-valid',
              questions: <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'implement_now',
                  'header': 'Implementation',
                  'question': 'Implement this plan?',
                  'options': <Map<String, dynamic>>[
                    <String, dynamic>{
                      'label': 'Yes, implement this plan',
                      'description': 'Proceed with implementation',
                    },
                  ],
                },
              ],
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await controller.submitUserInput(<String, dynamic>{
            'implement_now': <String, dynamic>{
              'answers': <String>['Yes, implement this plan'],
            },
          });
          fakeService.emitNotification('turn/completed', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-1',
              'threadId': 'thread-1',
              'status': 'completed',
            },
          });
        };
        controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        await controller.sendInput('build a plan');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(fakeService.respondUserInputCallCount, 1);
        final pending = controller.state.pendingUserInput;
        expect(pending, isNotNull);
        expect(pending?.source, PendingUserInputSource.localPlanFallback);
        expect(
          controller.state.activityLog.any(
            (line) =>
                line.contains('runtime/planFallback gate') &&
                line.contains('turnId=turn-1') &&
                line.contains('late=true'),
          ),
          isTrue,
        );
      },
    );

    test(
      'late fallback is not shown when plan mode is turned off before runInput returns',
      () async {
        final fakeService = _FakeSessionService();
        fakeService.runInputDelay = const Duration(milliseconds: 30);
        fakeService.onRunInputBeforeComplete = () async {
          fakeService.emitNotification('item/plan/delta', <String, dynamic>{
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'itemId': 'turn-1-plan',
            'delta': 'step 1',
          });
          fakeService.emitNotification('turn/completed', <String, dynamic>{
            'turn': <String, dynamic>{
              'id': 'turn-1',
              'threadId': 'thread-1',
              'status': 'completed',
            },
          });
        };
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();

        final sendFuture = controller.sendInput('build a plan');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        controller.togglePlanMode();
        await sendFuture;
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.planModeEnabled, isFalse);
        expect(controller.state.pendingUserInput, isNull);
        expect(
          controller.state.activityLog.any(
            (line) =>
                line.contains('runtime/planFallback gate') &&
                line.contains('planModeOn=false') &&
                line.contains('late=true'),
          ),
          isTrue,
        );
      },
    );

    test(
      'implementPlanFromChatAction sends explicit default collaboration reset',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        expect(controller.state.planModeEnabled, isTrue);

        await controller.implementPlanFromChatAction();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.planModeEnabled, isFalse);
        expect(fakeService.runInputCallCount, 1);
        expect(fakeService.lastRunInputText, 'Implement plan');
        expect(fakeService.lastRunInputPlanModeEnabled, isFalse);
        expect(fakeService.lastRunInputForceDefaultCollaborationMode, isTrue);
      },
    );

    test('implementPlanFromChatAction queued preserves reset intent', () async {
      final fakeService = _FakeSessionService();
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      await controller.selectWorkspaceFromPath('/repo');
      controller.togglePlanMode();
      await controller.sendInput('start running turn');

      fakeService.emitNotification('turn/started', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn-1',
          'threadId': 'thread-1',
          'status': 'inProgress',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.runningTurnCount, greaterThan(0));
      await controller.implementPlanFromChatAction();

      expect(controller.state.planModeEnabled, isFalse);
      expect(controller.state.pendingMessages.length, 1);
      final queued = controller.state.pendingMessages.first;
      expect(queued.text, 'Implement plan');
      expect(queued.planModeEnabled, isFalse);
      expect(queued.forceDefaultCollaborationMode, isTrue);
      expect(queued.attachments, isEmpty);
    });

    test('dequeued implement plan sends default collaboration reset', () async {
      final fakeService = _FakeSessionService();
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      await controller.selectWorkspaceFromPath('/repo');
      controller.togglePlanMode();
      await controller.sendInput('start running turn');

      fakeService.emitNotification('turn/started', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn-1',
          'threadId': 'thread-1',
          'status': 'inProgress',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await controller.implementPlanFromChatAction();
      fakeService.emitNotification('turn/completed', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn-1',
          'threadId': 'thread-1',
          'status': 'completed',
        },
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(fakeService.runInputCallCount, 2);
      expect(fakeService.lastRunInputText, 'Implement plan');
      expect(fakeService.lastRunInputPlanModeEnabled, isFalse);
      expect(fakeService.lastRunInputForceDefaultCollaborationMode, isTrue);
    });

    test('implementPlanFromChatAction sends with empty attachments', () async {
      final fakeService = _FakeSessionService();
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      await controller.selectWorkspaceFromPath('/repo');

      final tempDir = await Directory.systemTemp.createTemp(
        'alera_implement_plan_test_',
      );
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File('${tempDir.path}/context.txt');
      await file.writeAsString('extra attachment context');

      controller.addAttachment(
        ComposerAttachment(
          id: 'attachment-1',
          kind: AttachmentKind.file,
          path: file.path,
          displayName: 'context.txt',
          mimeType: 'text/plain',
        ),
      );
      expect(controller.state.composerAttachments.length, 1);

      await controller.implementPlanFromChatAction();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.composerAttachments, isEmpty);
      expect(fakeService.lastRunInputText, 'Implement plan');
      expect(fakeService.lastRunInputPlanModeEnabled, isFalse);
      expect(fakeService.lastRunInputForceDefaultCollaborationMode, isTrue);
      expect(fakeService.lastRunInputExtraInputItems, isEmpty);
    });

    test(
      'local plan fallback yes sends Implement plan and disables plan mode',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        await controller.sendInput('build a plan');

        fakeService.emitNotification('item/plan/delta', <String, dynamic>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'turn-1-plan',
          'delta': 'step 1',
        });
        fakeService.emitNotification('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await controller.submitUserInput(<String, dynamic>{
          'implement_plan': <String, dynamic>{
            'answers': <String>['Yes, implement this plan'],
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNull);
        expect(controller.state.planModeEnabled, isFalse);
        expect(fakeService.runInputCallCount, 2);
        expect(fakeService.lastRunInputText, 'Implement plan');
        expect(fakeService.lastRunInputPlanModeEnabled, isFalse);
        expect(fakeService.respondUserInputCallCount, 0);
      },
    );

    test(
      'local plan fallback no sends refinement and keeps plan mode enabled',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        await controller.sendInput('build a plan');

        fakeService.emitNotification('item/plan/delta', <String, dynamic>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'turn-1-plan',
          'delta': 'step 1',
        });
        fakeService.emitNotification('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await controller.submitUserInput(<String, dynamic>{
          'implement_plan': <String, dynamic>{
            'answers': <String>['Please split this into two commits'],
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNull);
        expect(controller.state.planModeEnabled, isTrue);
        expect(fakeService.runInputCallCount, 2);
        expect(
          fakeService.lastRunInputText,
          'Please split this into two commits',
        );
        expect(fakeService.lastRunInputPlanModeEnabled, isTrue);
        expect(fakeService.respondUserInputCallCount, 0);
      },
    );

    test(
      'local plan fallback dismiss closes card without RPC response',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        await controller.sendInput('build a plan');

        fakeService.emitNotification('item/plan/delta', <String, dynamic>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'turn-1-plan',
          'delta': 'step 1',
        });
        fakeService.emitNotification('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        controller.dismissUserInput();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNull);
        expect(fakeService.runInputCallCount, 1);
        expect(fakeService.respondUserInputCallCount, 0);
      },
    );

    test(
      'local plan fallback empty submit is ignored and keeps card visible',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        await controller.sendInput('build a plan');

        fakeService.emitNotification('item/plan/delta', <String, dynamic>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'turn-1-plan',
          'delta': 'step 1',
        });
        fakeService.emitNotification('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await controller.submitUserInput(const <String, dynamic>{});
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNotNull);
        expect(
          controller.state.pendingUserInput?.source,
          PendingUserInputSource.localPlanFallback,
        );
        expect(fakeService.runInputCallCount, 1);
        expect(fakeService.respondUserInputCallCount, 0);
        expect(
          controller.state.activityLog.any(
            (line) =>
                line.contains('runtime/userInput submitIgnored empty') &&
                line.contains('source=localPlanFallback') &&
                line.contains('turnId=turn-1'),
          ),
          isTrue,
        );
      },
    );

    test(
      'late backend user input request is auto-answered after local fallback resolution',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        controller.togglePlanMode();
        await controller.sendInput('build a plan');

        fakeService.emitNotification('item/plan/delta', <String, dynamic>{
          'threadId': 'thread-1',
          'turnId': 'turn-1',
          'itemId': 'turn-1-plan',
          'delta': 'step 1',
        });
        fakeService.emitNotification('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));
        controller.dismissUserInput();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        fakeService.emitRuntimeEvent(
          const SessionUserInputRequestEvent(
            requestId: 1100,
            threadId: 'thread-1',
            turnId: 'turn-1',
            itemId: 'late-request',
            questions: <Map<String, dynamic>>[
              <String, dynamic>{'id': 'q1', 'question': 'late'},
            ],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(controller.state.pendingUserInput, isNull);
        expect(fakeService.respondUserInputCallCount, 1);
        expect(fakeService.lastRespondUserInputRequestId, 1100);
        expect(fakeService.lastRespondUserInputAnswers, isEmpty);
        expect(
          controller.state.activityLog.any(
            (line) => line.contains('ignored late backend request'),
          ),
          isTrue,
        );
      },
    );

    test('/status does not append a timeline notice', () async {
      final fakeService = _FakeSessionService();
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      await controller.selectWorkspaceFromPath('/repo');

      await controller.sendInput('/status');

      expect(controller.state.timelineCells, isEmpty);
      expect(fakeService.runInputCallCount, 0);
    });

    test('/rename appends a descriptive system notice', () async {
      final fakeService = _FakeSessionService();
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      await controller.selectWorkspaceFromPath('/repo');
      await controller.sendInput('hello');

      await controller.sendInput('/rename Better name');

      final lastCell = controller.state.timelineCells.last;
      expect(lastCell.kind, TimelineCellKind.systemNotice);
      expect(lastCell.title, 'Thread renamed');
      expect(lastCell.markdownText, 'Thread renamed to Better name.');
    });

    test('startReviewFromPreset maps presets to typed targets', () async {
      final fakeService = _FakeSessionService();
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();
      await controller.selectWorkspaceFromPath('/repo');

      await controller.startReviewFromPreset(
        ReviewPresetSelection.baseBranch,
        value: 'origin/main',
      );
      expect(fakeService.lastReviewTarget, isA<CodexReviewBaseBranchTarget>());

      await controller.startReviewFromPreset(
        ReviewPresetSelection.commit,
        value: 'abc123',
      );
      expect(fakeService.lastReviewTarget, isA<CodexReviewCommitTarget>());

      await controller.startReviewFromPreset(
        ReviewPresetSelection.customInstructions,
        value: 'Focus on migrations',
      );
      expect(fakeService.lastReviewTarget, isA<CodexReviewCustomTarget>());

      await controller.startReviewFromPreset(
        ReviewPresetSelection.uncommittedChanges,
      );
      expect(
        fakeService.lastReviewTarget,
        isA<CodexReviewUncommittedChangesTarget>(),
      );
    });

    test(
      'logs stalled final_answer stream without clearing running turn count',
      () async {
        final fakeService = _FakeSessionService();
        var now = DateTime.utc(2026, 3, 8, 12);
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
          now: () => now,
          assistantStreamWarningGrace: const Duration(milliseconds: 20),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        await controller.sendInput('hello');

        fakeService.emitNotification('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'inProgress',
          },
        });
        fakeService.emitNotification(
          'codex/event/item_started',
          <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'item_started',
              'turn_id': 'turn-1',
              'item': <String, dynamic>{
                'id': 'msg-final',
                'type': 'AgentMessage',
                'phase': 'final_answer',
              },
            },
          },
        );
        fakeService
            .emitNotification('item/agentMessage/delta', <String, dynamic>{
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'itemId': 'msg-final',
              'delta': 'partial without close',
            });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        now = now.add(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 140));

        expect(
          controller.state.activityLog.any(
            (line) =>
                line.contains('runtime/assistantStream stalled') &&
                line.contains('turnId=turn-1') &&
                line.contains('itemId=msg-final') &&
                line.contains('signal=none'),
          ),
          isTrue,
        );
        expect(controller.state.runningTurnCount, 1);
      },
    );

    test(
      'ignores commentary-only legacy completion for terminal stream warnings',
      () async {
        final fakeService = _FakeSessionService();
        var now = DateTime.utc(2026, 3, 8, 12);
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
          now: () => now,
          assistantStreamWarningGrace: const Duration(milliseconds: 20),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        await controller.sendInput('hello');

        fakeService.emitNotification('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'inProgress',
          },
        });
        fakeService.emitNotification(
          'codex/event/item_completed',
          <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'item_completed',
              'turn_id': 'turn-1',
              'item': <String, dynamic>{
                'id': 'msg-commentary',
                'type': 'AgentMessage',
                'phase': 'commentary',
                'content': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'type': 'Text',
                    'text': 'legacy commentary',
                  },
                ],
              },
            },
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        now = now.add(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 140));

        expect(
          controller.state.activityLog.any(
            (line) =>
                line.contains(
                  'runtime/assistantStream missingTurnCompletion',
                ) &&
                line.contains('turnId=turn-1'),
          ),
          isFalse,
        );
      },
    );

    test(
      'logs missing turn completion after legacy assistant completion without clearing running turn count',
      () async {
        final fakeService = _FakeSessionService();
        var now = DateTime.utc(2026, 3, 8, 12);
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
          now: () => now,
          assistantStreamWarningGrace: const Duration(milliseconds: 20),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        await controller.sendInput('hello');

        fakeService.emitNotification('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'inProgress',
          },
        });
        fakeService.emitNotification(
          'codex/event/item_started',
          <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'item_started',
              'turn_id': 'turn-1',
              'item': <String, dynamic>{
                'id': 'msg-final',
                'type': 'AgentMessage',
                'phase': 'final_answer',
              },
            },
          },
        );
        fakeService
            .emitNotification('item/agentMessage/delta', <String, dynamic>{
              'threadId': 'thread-1',
              'turnId': 'turn-1',
              'itemId': 'msg-final',
              'delta': 'legacy final\n',
            });
        fakeService.emitNotification(
          'codex/event/item_completed',
          <String, dynamic>{
            'msg': <String, dynamic>{
              'type': 'item_completed',
              'turn_id': 'turn-1',
              'item': <String, dynamic>{
                'id': 'msg-final',
                'type': 'AgentMessage',
                'phase': 'final_answer',
                'content': <Map<String, dynamic>>[
                  <String, dynamic>{'type': 'text', 'text': 'legacy final'},
                ],
              },
            },
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        now = now.add(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 140));

        expect(
          controller.state.activityLog.any(
            (line) =>
                line.contains(
                  'runtime/assistantStream missingTurnCompletion',
                ) &&
                line.contains('turnId=turn-1') &&
                line.contains('itemId=msg-final') &&
                line.contains('signal=legacy_item_completed'),
          ),
          isTrue,
        );
        expect(controller.state.runningTurnCount, 1);
      },
    );

    test(
      'logs missing turn completion after modern assistant completion without clearing running turn count',
      () async {
        final fakeService = _FakeSessionService();
        var now = DateTime.utc(2026, 3, 8, 12);
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex', 'high', true),
          now: () => now,
          assistantStreamWarningGrace: const Duration(milliseconds: 20),
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();
        await controller.selectWorkspaceFromPath('/repo');
        await controller.sendInput('hello');

        fakeService.emitNotification('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-1',
            'threadId': 'thread-1',
            'status': 'inProgress',
          },
        });
        fakeService.emitNotification('item/completed', <String, dynamic>{
          'turnId': 'turn-1',
          'item': <String, dynamic>{
            'id': 'msg-final',
            'type': 'agentMessage',
            'phase': 'final_answer',
            'status': 'completed',
            'text': 'modern final',
          },
        });
        await Future<void>.delayed(const Duration(milliseconds: 20));

        now = now.add(const Duration(milliseconds: 40));
        await Future<void>.delayed(const Duration(milliseconds: 140));

        expect(
          controller.state.activityLog.any(
            (line) =>
                line.contains(
                  'runtime/assistantStream missingTurnCompletion',
                ) &&
                line.contains('turnId=turn-1') &&
                line.contains('itemId=msg-final') &&
                line.contains('signal=item_completed'),
          ),
          isTrue,
        );
        expect(controller.state.runningTurnCount, 1);
      },
    );

    test('activateChat hydrates timeline from persisted messages', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.3-codex', 'high', true);
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();

      final now = DateTime.utc(2026, 5, 1, 12);
      final project = Project(
        id: 'project-1',
        name: 'alera',
        repoPath: '/repo',
        createdAt: now,
        updatedAt: now,
      );
      final chatId = 'chat-1';
      final session = AleraSession(
        id: chatId,
        request: SessionCreateRequest(
          projectPath: project.repoPath,
          firstPrompt: '',
          model: 'gpt-5.3-codex',
          projectId: project.id,
        ),
        workspacePath: project.repoPath,
        createdAt: now,
        updatedAt: now,
        title: 'existing chat',
        model: 'gpt-5.3-codex',
        threadId: 'thread-1',
        projectId: project.id,
      );
      fakeService.adoptPersistedSession(session);
      fakeService.seedPersistedMessages(chatId, <ChatMessage>[
        ChatMessage(
          chatId: chatId,
          seq: 0,
          role: ChatMessageRole.user,
          text: 'hola',
          createdAt: now,
        ),
        ChatMessage(
          chatId: chatId,
          seq: 1,
          role: ChatMessageRole.assistant,
          text: '¡hola! ¿en qué te ayudo?',
          turnId: 'turn-7',
          createdAt: now.add(const Duration(seconds: 2)),
        ),
      ]);

      final summary = ChatSummary(
        id: chatId,
        projectId: project.id,
        title: 'existing chat',
        model: 'gpt-5.3-codex',
        threadId: 'thread-1',
        createdAt: now,
        updatedAt: now,
      );

      await controller.activateChat(chat: summary, project: project);

      final cells = controller.state.timelineCells;
      expect(cells.length, 2);
      expect(cells[0].kind, TimelineCellKind.userMessage);
      expect(cells[0].markdownText, 'hola');
      expect(cells[0].turnId, 'turn-7');
      expect(cells[0].metadata['historic'], isTrue);
      expect(cells[1].kind, TimelineCellKind.assistantMessage);
      expect(cells[1].markdownText, '¡hola! ¿en qué te ayudo?');
      expect(cells[1].turnId, 'turn-7');
      expect(cells[1].metadata['historic'], isTrue);
    });

    test('activateChat hydrates timeline from persisted cells with reasoning '
        'and tool calls', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.3-codex', 'high', true);
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();

      final now = DateTime.utc(2026, 5, 1, 14);
      final project = Project(
        id: 'project-2',
        name: 'alera',
        repoPath: '/repo',
        createdAt: now,
        updatedAt: now,
      );
      final chatId = 'chat-2';
      fakeService.adoptPersistedSession(
        AleraSession(
          id: chatId,
          request: SessionCreateRequest(
            projectPath: project.repoPath,
            firstPrompt: '',
            model: 'gpt-5.3-codex',
            projectId: project.id,
          ),
          workspacePath: project.repoPath,
          createdAt: now,
          updatedAt: now,
          title: 'snapshot chat',
          model: 'gpt-5.3-codex',
          threadId: 'thread-snap',
          projectId: project.id,
        ),
      );
      fakeService.seedPersistedCells(chatId, <TimelineCell>[
        TimelineCell(
          id: 'user-1',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          createdAt: now,
          updatedAt: now,
          markdownText: 'lista los archivos',
        ),
        TimelineCell(
          id: 'reasoning-1',
          kind: TimelineCellKind.reasoning,
          status: TimelineCellStatus.completed,
          createdAt: now.add(const Duration(seconds: 1)),
          updatedAt: now.add(const Duration(seconds: 1)),
          markdownText: 'pensando un momento...',
          turnId: 'turn-snap',
        ),
        TimelineCell(
          id: 'tool-1',
          kind: TimelineCellKind.toolCall,
          status: TimelineCellStatus.completed,
          createdAt: now.add(const Duration(seconds: 2)),
          updatedAt: now.add(const Duration(seconds: 2)),
          title: 'shell',
          detailsText: 'ls -la',
          turnId: 'turn-snap',
        ),
        TimelineCell(
          id: 'assistant-final-turn-snap',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          createdAt: now.add(const Duration(seconds: 3)),
          updatedAt: now.add(const Duration(seconds: 3)),
          markdownText: 'aquí están los archivos.',
          turnId: 'turn-snap',
        ),
      ]);

      final summary = ChatSummary(
        id: chatId,
        projectId: project.id,
        title: 'snapshot chat',
        model: 'gpt-5.3-codex',
        threadId: 'thread-snap',
        createdAt: now,
        updatedAt: now,
      );

      await controller.activateChat(chat: summary, project: project);

      final cells = controller.state.timelineCells;
      expect(cells.length, 4);
      expect(cells.map((c) => c.kind).toList(), <TimelineCellKind>[
        TimelineCellKind.userMessage,
        TimelineCellKind.reasoning,
        TimelineCellKind.toolCall,
        TimelineCellKind.assistantMessage,
      ]);
      expect(cells[1].markdownText, 'pensando un momento...');
      expect(cells[2].title, 'shell');
      expect(cells[2].detailsText, 'ls -la');
      expect(cells[3].markdownText, 'aquí están los archivos.');
      for (final cell in cells) {
        expect(cell.isStreaming, isFalse);
      }
    });

    test(
      'activateChat restores running turn counter so the composer shows stop',
      () async {
        final fakeService = _FakeSessionService();
        final fakeSettings = _FakeSettingsService(
          'gpt-5.3-codex',
          'high',
          true,
        );
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: fakeSettings,
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();

        final now = DateTime.utc(2026, 5, 1, 16);
        final project = Project(
          id: 'project-3',
          name: 'alera',
          repoPath: '/repo',
          createdAt: now,
          updatedAt: now,
        );
        final chatId = 'chat-3';
        fakeService.adoptPersistedSession(
          AleraSession(
            id: chatId,
            request: SessionCreateRequest(
              projectPath: project.repoPath,
              firstPrompt: '',
              model: 'gpt-5.3-codex',
              projectId: project.id,
            ),
            workspacePath: project.repoPath,
            createdAt: now,
            updatedAt: now,
            title: 'mid-flight chat',
            model: 'gpt-5.3-codex',
            threadId: 'thread-3',
            lastTurnId: 'turn-live',
            projectId: project.id,
          ),
        );
        // Emit a turn/started notification so the controller registers the
        // running turn before the user navigates back to the chat.
        fakeService.emitEvent(
          SessionNotificationEvent(
            method: 'turn/started',
            payload: <String, dynamic>{
              'params': <String, dynamic>{
                'turn': <String, dynamic>{
                  'id': 'turn-live',
                  'threadId': 'thread-3',
                },
              },
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final summary = ChatSummary(
          id: chatId,
          projectId: project.id,
          title: 'mid-flight chat',
          model: 'gpt-5.3-codex',
          threadId: 'thread-3',
          lastTurnId: 'turn-live',
          createdAt: now,
          updatedAt: now,
        );

        await controller.activateChat(chat: summary, project: project);

        expect(controller.state.runningTurnCount, 1);
        expect(controller.state.activeTurnId, 'turn-live');
      },
    );

    test('switching chats preserves each chat pending queue', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.3-codex', 'high', true);
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();

      final now = DateTime.utc(2026, 5, 1, 20);
      final project = Project(
        id: 'project-queue',
        name: 'alera',
        repoPath: '/repo',
        createdAt: now,
        updatedAt: now,
      );
      final chatA = AleraSession(
        id: 'chat-a',
        request: SessionCreateRequest(
          projectPath: project.repoPath,
          firstPrompt: '',
          model: 'gpt-5.3-codex',
          projectId: project.id,
        ),
        workspacePath: project.repoPath,
        createdAt: now,
        updatedAt: now,
        title: 'chat a',
        model: 'gpt-5.3-codex',
        threadId: 'thread-a',
        projectId: project.id,
      );
      final chatB = AleraSession(
        id: 'chat-b',
        request: SessionCreateRequest(
          projectPath: project.repoPath,
          firstPrompt: '',
          model: 'gpt-5.3-codex',
          projectId: project.id,
        ),
        workspacePath: project.repoPath,
        createdAt: now,
        updatedAt: now,
        title: 'chat b',
        model: 'gpt-5.3-codex',
        threadId: 'thread-b',
        projectId: project.id,
      );
      fakeService.adoptPersistedSession(chatA);
      fakeService.adoptPersistedSession(chatB);

      await controller.activateChat(
        chat: ChatSummary(
          id: chatA.id,
          projectId: project.id,
          title: chatA.title,
          model: chatA.model,
          threadId: chatA.threadId,
          createdAt: now,
          updatedAt: now,
        ),
        project: project,
      );
      fakeService.emitNotification('turn/started', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn-a',
          'threadId': 'thread-a',
          'status': 'inProgress',
        },
      });
      await Future<void>.delayed(Duration.zero);
      await controller.sendInput('queued for chat a');
      expect(controller.state.pendingMessages.single.text, 'queued for chat a');

      await controller.activateChat(
        chat: ChatSummary(
          id: chatB.id,
          projectId: project.id,
          title: chatB.title,
          model: chatB.model,
          threadId: chatB.threadId,
          createdAt: now,
          updatedAt: now,
        ),
        project: project,
      );
      expect(controller.state.pendingMessages, isEmpty);
      fakeService.emitNotification('turn/started', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn-b',
          'threadId': 'thread-b',
          'status': 'inProgress',
        },
      });
      await Future<void>.delayed(Duration.zero);
      await controller.sendInput('queued for chat b');
      expect(controller.state.pendingMessages.single.text, 'queued for chat b');

      await controller.activateChat(
        chat: ChatSummary(
          id: chatA.id,
          projectId: project.id,
          title: chatA.title,
          model: chatA.model,
          threadId: chatA.threadId,
          createdAt: now,
          updatedAt: now,
        ),
        project: project,
      );
      expect(controller.state.pendingMessages.single.text, 'queued for chat a');
      final queuedAId = controller.state.pendingMessages.single.id;
      await controller.steerQueuedMessage(queuedAId);
      expect(fakeService.steerActiveTurnCallCount, 1);
      expect(fakeService.lastSteerSessionId, chatA.id);
      expect(fakeService.lastSteerExpectedTurnId, 'turn-a');
      expect(fakeService.lastSteerRawInput, 'queued for chat a');
      expect(controller.state.pendingMessages, isEmpty);

      await controller.activateChat(
        chat: ChatSummary(
          id: chatB.id,
          projectId: project.id,
          title: chatB.title,
          model: chatB.model,
          threadId: chatB.threadId,
          createdAt: now,
          updatedAt: now,
        ),
        project: project,
      );
      expect(controller.state.pendingMessages.single.text, 'queued for chat b');
    });

    test(
      'background chat streaming is restored when returning to the chat',
      () async {
        final fakeService = _FakeSessionService();
        final fakeSettings = _FakeSettingsService(
          'gpt-5.3-codex',
          'high',
          true,
        );
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: fakeSettings,
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();

        final now = DateTime.utc(2026, 5, 1, 21);
        final project = Project(
          id: 'project-bg',
          name: 'alera',
          repoPath: '/repo',
          createdAt: now,
          updatedAt: now,
        );
        final chatA = AleraSession(
          id: 'chat-bg-a',
          request: SessionCreateRequest(
            projectPath: project.repoPath,
            firstPrompt: '',
            model: 'gpt-5.3-codex',
            projectId: project.id,
          ),
          workspacePath: project.repoPath,
          createdAt: now,
          updatedAt: now,
          title: 'chat background a',
          model: 'gpt-5.3-codex',
          threadId: 'thread-bg-a',
          projectId: project.id,
        );
        final chatB = AleraSession(
          id: 'chat-bg-b',
          request: SessionCreateRequest(
            projectPath: project.repoPath,
            firstPrompt: '',
            model: 'gpt-5.3-codex',
            projectId: project.id,
          ),
          workspacePath: project.repoPath,
          createdAt: now,
          updatedAt: now,
          title: 'chat background b',
          model: 'gpt-5.3-codex',
          threadId: 'thread-bg-b',
          projectId: project.id,
        );
        fakeService.adoptPersistedSession(chatA);
        fakeService.adoptPersistedSession(chatB);

        await controller.activateChat(
          chat: ChatSummary(
            id: chatA.id,
            projectId: project.id,
            title: chatA.title,
            model: chatA.model,
            threadId: chatA.threadId,
            createdAt: now,
            updatedAt: now,
          ),
          project: project,
        );
        fakeService.emitNotification('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-bg-a',
            'threadId': 'thread-bg-a',
            'status': 'inProgress',
          },
        });
        await Future<void>.delayed(Duration.zero);

        await controller.activateChat(
          chat: ChatSummary(
            id: chatB.id,
            projectId: project.id,
            title: chatB.title,
            model: chatB.model,
            threadId: chatB.threadId,
            createdAt: now,
            updatedAt: now,
          ),
          project: project,
        );

        fakeService.emitNotification('background/event', <String, dynamic>{
          'kind': 'background_terminal_waiting',
          'message': 'waiting in background session',
        });
        await Future<void>.delayed(Duration.zero);
        expect(controller.state.statusHeader, isNull);

        fakeService.emitNotification('item/started', <String, dynamic>{
          'threadId': 'thread-bg-a',
          'turnId': 'turn-bg-a',
          'item': <String, dynamic>{
            'id': 'msg-bg-a',
            'type': 'agentMessage',
            'phase': 'final_answer',
          },
        });
        fakeService.emitNotification(
          'item/agentMessage/delta',
          <String, dynamic>{
            'turnId': 'turn-bg-a',
            'itemId': 'msg-bg-a',
            'delta': 'background answer\n',
          },
        );
        fakeService.emitNotification('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-bg-a',
            'threadId': 'thread-bg-a',
            'status': 'completed',
          },
        });
        await Future<void>.delayed(Duration.zero);

        expect(controller.state.activeSessionId, chatB.id);
        expect(
          controller.state.timelineCells
              .where((cell) => cell.markdownText == 'background answer')
              .length,
          0,
        );

        await controller.activateChat(
          chat: ChatSummary(
            id: chatA.id,
            projectId: project.id,
            title: chatA.title,
            model: chatA.model,
            threadId: chatA.threadId,
            createdAt: now,
            updatedAt: now,
          ),
          project: project,
        );

        expect(controller.state.runningTurnCount, 0);
        expect(
          controller.state.timelineCells.any(
            (cell) =>
                cell.kind == TimelineCellKind.assistantMessage &&
                cell.markdownText == 'background answer',
          ),
          isTrue,
        );
      },
    );

    test('switching back does not overwrite a saved chat snapshot', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.3-codex', 'high', true);
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();

      final now = DateTime.utc(2026, 5, 1, 21, 30);
      final project = Project(
        id: 'project-switch-race',
        name: 'alera',
        repoPath: '/repo',
        createdAt: now,
        updatedAt: now,
      );
      final chatA = AleraSession(
        id: 'chat-race-a',
        request: SessionCreateRequest(
          projectPath: project.repoPath,
          firstPrompt: '',
          model: 'gpt-5.3-codex',
          projectId: project.id,
        ),
        workspacePath: project.repoPath,
        createdAt: now,
        updatedAt: now,
        title: 'chat race a',
        model: 'gpt-5.3-codex',
        threadId: 'thread-race-a',
        projectId: project.id,
      );
      final chatB = AleraSession(
        id: 'chat-race-b',
        request: SessionCreateRequest(
          projectPath: project.repoPath,
          firstPrompt: '',
          model: 'gpt-5.3-codex',
          projectId: project.id,
        ),
        workspacePath: project.repoPath,
        createdAt: now,
        updatedAt: now,
        title: 'chat race b',
        model: 'gpt-5.3-codex',
        threadId: 'thread-race-b',
        projectId: project.id,
      );
      fakeService.adoptPersistedSession(chatA);
      fakeService.adoptPersistedSession(chatB);

      await controller.activateChat(
        chat: ChatSummary(
          id: chatA.id,
          projectId: project.id,
          title: chatA.title,
          model: chatA.model,
          threadId: chatA.threadId,
          createdAt: now,
          updatedAt: now,
        ),
        project: project,
      );
      fakeService.emitNotification('turn/started', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn-race-a',
          'threadId': 'thread-race-a',
          'status': 'inProgress',
        },
      });
      fakeService.emitNotification('item/started', <String, dynamic>{
        'threadId': 'thread-race-a',
        'turnId': 'turn-race-a',
        'item': <String, dynamic>{
          'id': 'msg-race-a',
          'type': 'agentMessage',
          'phase': 'final_answer',
        },
      });
      fakeService.emitNotification('item/agentMessage/delta', <String, dynamic>{
        'turnId': 'turn-race-a',
        'itemId': 'msg-race-a',
        'delta': 'preserved answer\n',
      });
      await Future<void>.delayed(Duration.zero);

      await controller.activateChat(
        chat: ChatSummary(
          id: chatB.id,
          projectId: project.id,
          title: chatB.title,
          model: chatB.model,
          threadId: chatB.threadId,
          createdAt: now,
          updatedAt: now,
        ),
        project: project,
      );

      fakeService.onSetActiveSessionBeforeComplete = (sessionId) async {
        if (sessionId != chatA.id) {
          return;
        }
        fakeService.emitNotification(
          'item/agentMessage/delta',
          <String, dynamic>{
            'turnId': 'turn-race-a',
            'itemId': 'msg-race-a',
            'delta': 'late delta\n',
          },
        );
        await Future<void>.delayed(Duration.zero);
      };

      await controller.activateChat(
        chat: ChatSummary(
          id: chatA.id,
          projectId: project.id,
          title: chatA.title,
          model: chatA.model,
          threadId: chatA.threadId,
          createdAt: now,
          updatedAt: now,
        ),
        project: project,
      );

      final assistantText = controller.state.timelineCells
          .where((cell) => cell.kind == TimelineCellKind.assistantMessage)
          .map((cell) => cell.markdownText)
          .join('\n');
      expect(assistantText, contains('preserved answer'));
      expect(assistantText, contains('late delta'));
    });

    test('background events do not render into a new chat stub', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.3-codex', 'high', true);
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();

      final now = DateTime.utc(2026, 5, 1, 22);
      final projectA = Project(
        id: 'project-stub-a',
        name: 'orca',
        repoPath: '/repo',
        createdAt: now,
        updatedAt: now,
      );
      final projectB = Project(
        id: 'project-stub-b',
        name: 'other',
        repoPath: '/other',
        createdAt: now,
        updatedAt: now,
      );
      final chatA = AleraSession(
        id: 'chat-stub-a',
        request: SessionCreateRequest(
          projectPath: projectA.repoPath,
          firstPrompt: '',
          model: 'gpt-5.3-codex',
          projectId: projectA.id,
        ),
        workspacePath: projectA.repoPath,
        createdAt: now,
        updatedAt: now,
        title: 'chat a',
        model: 'gpt-5.3-codex',
        threadId: 'thread-stub-a',
        projectId: projectA.id,
      );
      fakeService.adoptPersistedSession(chatA);

      await controller.activateChat(
        chat: ChatSummary(
          id: chatA.id,
          projectId: projectA.id,
          title: chatA.title,
          model: chatA.model,
          threadId: chatA.threadId,
          createdAt: now,
          updatedAt: now,
        ),
        project: projectA,
      );
      fakeService.emitNotification('turn/started', <String, dynamic>{
        'turn': <String, dynamic>{
          'id': 'turn-stub-a',
          'threadId': 'thread-stub-a',
          'status': 'inProgress',
        },
      });
      await Future<void>.delayed(Duration.zero);

      await controller.activateChatStub(project: projectB);
      expect(controller.state.activeSessionId, isNull);
      expect(controller.state.timelineCells, isEmpty);

      fakeService.emitNotification('background/event', <String, dynamic>{
        'kind': 'background_terminal_waiting',
        'message': 'waiting in background session',
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.timelineCells, isEmpty);
      expect(controller.state.statusHeader, isNull);
    });

    test('activateChat clears queued messages from a previous chat', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.3-codex', 'high', true);
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _FakeProjectService(),
        settingsService: fakeSettings,
      );
      addTearDown(() async {
        controller.dispose();
        await fakeService.shutdown();
      });

      await controller.bootstrap();

      controller.state = controller.state.copyWith(
        pendingMessages: <PendingMessage>[
          PendingMessage(
            id: 'queued-1',
            text: 'leftover from chat A',
            attachments: const <ComposerAttachment>[],
            draftItems: const <ComposerDraftItem>[],
            planModeEnabled: false,
            speedMode: 'normal',
            forceDefaultCollaborationMode: false,
          ),
        ],
      );

      final now = DateTime.utc(2026, 5, 1, 19);
      final project = Project(
        id: 'project-5',
        name: 'alera',
        repoPath: '/repo',
        createdAt: now,
        updatedAt: now,
      );
      const chatId = 'chat-5';
      fakeService.adoptPersistedSession(
        AleraSession(
          id: chatId,
          request: SessionCreateRequest(
            projectPath: project.repoPath,
            firstPrompt: '',
            model: 'gpt-5.3-codex',
            projectId: project.id,
          ),
          workspacePath: project.repoPath,
          createdAt: now,
          updatedAt: now,
          title: 'fresh chat',
          model: 'gpt-5.3-codex',
          threadId: 'thread-5',
          projectId: project.id,
        ),
      );

      final summary = ChatSummary(
        id: chatId,
        projectId: project.id,
        title: 'fresh chat',
        model: 'gpt-5.3-codex',
        threadId: 'thread-5',
        createdAt: now,
        updatedAt: now,
      );

      // Simulate the user already being in a different chat before switching.
      controller.state = controller.state.copyWith(
        activeSessionId: 'previous-chat',
      );

      await controller.activateChat(chat: summary, project: project);

      expect(controller.state.pendingMessages, isEmpty);
      expect(controller.state.composerAttachments, isEmpty);
      expect(controller.state.composerDraftItems, isEmpty);
      expect(controller.state.editingPendingMessageId, isNull);
    });

    test(
      'activateChat clears running turn when generation finished while away',
      () async {
        final fakeService = _FakeSessionService();
        final fakeSettings = _FakeSettingsService(
          'gpt-5.3-codex',
          'high',
          true,
        );
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: fakeSettings,
        );
        addTearDown(() async {
          controller.dispose();
          await fakeService.shutdown();
        });

        await controller.bootstrap();

        final now = DateTime.utc(2026, 5, 1, 18);
        final project = Project(
          id: 'project-4',
          name: 'alera',
          repoPath: '/repo',
          createdAt: now,
          updatedAt: now,
        );
        const chatId = 'chat-4';
        const threadId = 'thread-4';
        const turnId = 'turn-finished';
        fakeService.adoptPersistedSession(
          AleraSession(
            id: chatId,
            request: SessionCreateRequest(
              projectPath: project.repoPath,
              firstPrompt: '',
              model: 'gpt-5.3-codex',
              projectId: project.id,
            ),
            workspacePath: project.repoPath,
            createdAt: now,
            updatedAt: now,
            title: 'finished chat',
            model: 'gpt-5.3-codex',
            threadId: threadId,
            lastTurnId: turnId,
            projectId: project.id,
          ),
        );

        // Simulate the turn that started and then completed while the user
        // was viewing a different chat.
        fakeService.emitEvent(
          SessionNotificationEvent(
            method: 'turn/started',
            payload: <String, dynamic>{
              'params': <String, dynamic>{
                'turn': <String, dynamic>{'id': turnId, 'threadId': threadId},
              },
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);
        fakeService.emitEvent(
          SessionNotificationEvent(
            method: 'turn/completed',
            payload: <String, dynamic>{
              'params': <String, dynamic>{
                'turn': <String, dynamic>{'id': turnId, 'threadId': threadId},
              },
            },
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final summary = ChatSummary(
          id: chatId,
          projectId: project.id,
          title: 'finished chat',
          model: 'gpt-5.3-codex',
          threadId: threadId,
          lastTurnId: turnId,
          createdAt: now,
          updatedAt: now,
        );

        await controller.activateChat(chat: summary, project: project);

        expect(controller.state.runningTurnCount, 0);
        expect(controller.state.activeTurnId, isNull);
      },
    );
  });
}
