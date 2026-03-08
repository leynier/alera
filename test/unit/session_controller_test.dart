import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_service.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
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
  bool? lastRunInputPlanModeEnabled;
  bool? lastRunInputForceDefaultCollaborationMode;
  List<Map<String, dynamic>> lastRunInputExtraInputItems =
      const <Map<String, dynamic>>[];
  int interruptCallCount = 0;
  String? interruptedSessionId;
  String? interruptedTurnOverride;
  int respondUserInputCallCount = 0;
  Object? lastRespondUserInputRequestId;
  Map<String, dynamic>? lastRespondUserInputAnswers;
  CodexReviewTarget? lastReviewTarget;
  Duration runInputDelay = Duration.zero;
  Future<void> Function()? onRunInputBeforeComplete;

  @override
  Stream<SessionRuntimeEvent> get events => _eventsController.stream;

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
    List<Map<String, dynamic>> extraInputItems = const <Map<String, dynamic>>[],
    bool planModeEnabled = false,
    bool forceDefaultCollaborationMode = false,
    String approvalPolicy = 'never',
  }) async {
    runInputCallCount += 1;
    lastRunInputText = rawInput;
    lastRunInputReasoningEffort = reasoningEffort;
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
    return existing;
  }

  @override
  Future<void> shutdown() async {
    await _eventsController.close();
  }

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
    this._markdownEnabled,
  );

  String _selectedModel;
  String _selectedReasoningEffort;
  bool _markdownEnabled;
  int saveCallCount = 0;

  @override
  Future<SettingsSnapshot> load() async {
    return SettingsSnapshot(
      selectedModel: _selectedModel,
      selectedReasoningEffort: _selectedReasoningEffort,
      markdownEnabled: _markdownEnabled,
    );
  }

  @override
  Future<void> save(SettingsSnapshot snapshot) async {
    saveCallCount += 1;
    _selectedModel = snapshot.selectedModel;
    _selectedReasoningEffort = snapshot.selectedReasoningEffort;
    _markdownEnabled = snapshot.markdownEnabled;
  }

  String get selectedModel => _selectedModel;
  String get selectedReasoningEffort => _selectedReasoningEffort;
  bool get markdownEnabled => _markdownEnabled;
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
        controller.state.connectionState,
        AppServerConnectionState.connected,
      );
    });

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
  });
}
