import 'dart:async';

import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_service.dart';
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
  int interruptCallCount = 0;
  String? interruptedSessionId;
  String? interruptedTurnOverride;

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
  Future<void> runInput({
    required String sessionId,
    required String rawInput,
  }) async {
    runInputCallCount += 1;
    lastRunInputText = rawInput;
    final existing = _sessionsById[sessionId];
    if (existing == null) {
      throw StateError('session not found');
    }
    _sessionsById[sessionId] = existing.copyWith(
      lastTurnId: 'turn-1',
      updatedAt: DateTime.now().toUtc(),
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
}

class _FakeProjectService implements ProjectService {
  @override
  Future<bool> isGitRepository(String path) async => true;

  @override
  Future<ProjectValidationResult> validateGitRepository(String path) async {
    return ProjectValidationResult.ok();
  }
}

class _FakeSettingsService implements SettingsService {
  _FakeSettingsService(this._selectedModel);

  String _selectedModel;
  int saveCallCount = 0;

  @override
  Future<SettingsSnapshot> load() async {
    return SettingsSnapshot(selectedModel: _selectedModel);
  }

  @override
  Future<void> save(SettingsSnapshot snapshot) async {
    saveCallCount += 1;
    _selectedModel = snapshot.selectedModel;
  }

  String get selectedModel => _selectedModel;
}

void main() {
  group('session controller', () {
    test('selectWorkspace without existing session boots connection', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.3-codex');
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
    });

    test('sendInput lazily creates session on first prompt', () async {
      final fakeService = _FakeSessionService();
      final fakeSettings = _FakeSettingsService('gpt-5.3-codex');
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
        final fakeSettings = _FakeSettingsService('gpt-5.3-codex');
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
        expect(fakeSettings.saveCallCount, greaterThan(0));
      },
    );

    test(
      'interruptActiveTurn toggles state and clears on turn completion',
      () async {
        final fakeService = _FakeSessionService();
        final controller = SessionController(
          sessionService: fakeService,
          projectService: _FakeProjectService(),
          settingsService: _FakeSettingsService('gpt-5.3-codex'),
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
        settingsService: _FakeSettingsService('gpt-5.3-codex'),
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
  });
}
