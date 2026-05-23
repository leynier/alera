import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/domain/chat_message.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_brand_row.dart';
import 'package:alera/src/features/projects/presentation/widgets/sidebar_search_bar.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_service.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/presentation/session_workspace_view.dart';
import 'package:alera/src/features/session/domain/pending_approval.dart';
import 'package:alera/src/features/settings/application/settings_service.dart';
import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
import 'package:alera/src/features/shell/presentation/alera_status_bar.dart';
import 'package:alera/src/features/shell/presentation/alera_top_bar.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ShellFakeSessionService implements SessionService {
  _ShellFakeSessionService({
    List<AleraSession> sessions = const <AleraSession>[],
  }) : _sessions = List<AleraSession>.of(sessions);

  final StreamController<SessionRuntimeEvent> _eventsController =
      StreamController<SessionRuntimeEvent>.broadcast();
  final List<AleraSession> _sessions;

  @override
  Stream<SessionRuntimeEvent> get events => _eventsController.stream;

  @override
  List<AleraSession> get sessions => List<AleraSession>.unmodifiable(_sessions);

  @override
  Future<void> ensureConnected() async {}

  @override
  AleraSession? findLatestSessionForWorkspace(String workspacePath) {
    for (final session in _sessions.reversed) {
      if (session.workspacePath == workspacePath) {
        return session;
      }
    }
    return null;
  }

  @override
  Future<AleraSession> createSession(SessionCreateRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<void> interruptActiveTurn({
    required String sessionId,
    String? turnIdOverride,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> compactContext({required String sessionId}) {
    throw UnimplementedError();
  }

  @override
  Future<String> steerActiveTurn({
    required String sessionId,
    required String rawInput,
    required String expectedTurnId,
    List<Map<String, dynamic>> extraInputItems = const <Map<String, dynamic>>[],
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
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
  ) async {}

  @override
  Future<void> renameSessionThread({
    required String sessionId,
    required String name,
  }) {
    throw UnimplementedError();
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
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<CodexCollaborationModePreset>> listCollaborationModes() {
    throw UnimplementedError();
  }

  @override
  Future<List<CodexSkillsListEntry>> listSkills({
    List<String>? cwds,
    bool forceReload = false,
    List<CodexSkillsListExtraRootsForCwd>? perCwdExtraUserRoots,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<CodexAppsPage> listApps({
    String? sessionId,
    String? cursor,
    int? limit,
    bool forceRefetch = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AleraSession> setActiveSession(String sessionId) async {
    return _sessions.firstWhere((session) => session.id == sessionId);
  }

  @override
  Future<void> shutdown() async {
    await _eventsController.close();
  }

  @override
  Future<void> updateSessionModel({
    required String sessionId,
    required String modelId,
  }) {
    throw UnimplementedError();
  }

  @override
  AleraSession? findSessionById(String sessionId) {
    for (final session in _sessions) {
      if (session.id == sessionId) {
        return session;
      }
    }
    return null;
  }

  @override
  void adoptPersistedSession(AleraSession session) {
    _sessions.add(session);
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    _sessions.removeWhere((s) => s.id == sessionId);
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
  }) async {}

  @override
  Future<List<ChatMessage>> loadPersistedMessages(String chatId) async {
    return const <ChatMessage>[];
  }

  @override
  Future<List<TimelineCell>> loadPersistedCells(String chatId) async {
    return const <TimelineCell>[];
  }

  @override
  Future<void> persistTimelineCells({
    required String sessionId,
    required List<TimelineCell> cells,
  }) async {}

  @override
  int runningTurnCountFor(String sessionId) => 0;

  @override
  String? activeTurnIdFor(String sessionId) => null;
}

class _ShellFakeProjectService implements ProjectService {
  @override
  Future<bool> isGitRepository(String path) async => true;

  @override
  Future<ProjectValidationResult> validateGitRepository(String path) async {
    return ProjectValidationResult.ok();
  }

  @override
  Future<List<String>> listGitBranches(String path) async {
    return const <String>['main', 'origin/main'];
  }
}

class _ShellFakeSettingsService implements SettingsService {
  _ShellFakeSettingsService(
    this._selectedModel,
    this._selectedReasoningEffort,
    this._markdownEnabled,
  ) : _planModeEnabled = false,
      _selectedSpeedMode = 'normal',
      _permissionMode = PermissionMode.defaultMode;

  String _selectedModel;
  String _selectedReasoningEffort;
  String _selectedSpeedMode;
  bool _markdownEnabled;
  bool _planModeEnabled;
  PermissionMode _permissionMode;

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
    _selectedModel = snapshot.selectedModel;
    _selectedReasoningEffort = snapshot.selectedReasoningEffort;
    _selectedSpeedMode = snapshot.selectedSpeedMode;
    _markdownEnabled = snapshot.markdownEnabled;
    _planModeEnabled = snapshot.planModeEnabled;
    _permissionMode = snapshot.permissionMode;
  }
}

void main() {
  AleraSession buildSession({
    required String id,
    required String workspacePath,
    String title = 'session',
  }) {
    final now = DateTime.utc(2026, 3, 15);
    return AleraSession(
      id: id,
      request: SessionCreateRequest(
        projectPath: workspacePath,
        firstPrompt: 'hello',
        model: 'gpt-5.3-codex',
      ),
      workspacePath: workspacePath,
      createdAt: now,
      updatedAt: now,
      title: title,
      model: 'gpt-5.3-codex',
    );
  }

  Future<(SessionController, _ShellFakeSessionService)> buildController({
    List<AleraSession> sessions = const <AleraSession>[],
  }) async {
    final fakeService = _ShellFakeSessionService(sessions: sessions);
    final controller = SessionController(
      sessionService: fakeService,
      projectService: _ShellFakeProjectService(),
      settingsService: _ShellFakeSettingsService('gpt-5.3-codex', 'high', true),
    );
    await controller.bootstrap();
    return (controller, fakeService);
  }

  Future<Database> openMemoryDb() {
    return databaseFactoryMemory.openDatabase('test.db');
  }

  testWidgets('sidebar brand row aligns with top bar height', (tester) async {
    final (controller, fakeService) = await buildController();
    addTearDown(() async {
      await fakeService.shutdown();
    });
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await controller.selectWorkspaceFromPath('/repo');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraDatabaseProvider.overrideWith(
            (ref) async => await openMemoryDb(),
          ),
          sessionControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: AleraShellPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final topBarRect = tester.getRect(find.byType(AleraTopBar));
    final sidebarBrandRect = tester.getRect(find.byType(SidebarBrandRow));

    expect(sidebarBrandRect.height, AleraTokens.topBarHeight);
    expect((sidebarBrandRect.top - topBarRect.top).abs(), lessThan(1.0));
    expect((sidebarBrandRect.bottom - topBarRect.bottom).abs(), lessThan(1.0));
  });

  testWidgets('expanded sidebar omits primary new chat action', (tester) async {
    final (controller, fakeService) = await buildController();
    addTearDown(() async {
      await fakeService.shutdown();
    });

    await controller.selectWorkspaceFromPath('/repo');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraDatabaseProvider.overrideWith(
            (ref) async => await openMemoryDb(),
          ),
          sessionControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: AleraShellPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final sidebarBrandRect = tester.getRect(find.byType(SidebarBrandRow));
    final searchRect = tester.getRect(find.byType(SidebarSearchBar));

    expect(find.text('New chat'), findsNothing);
    expect(find.byTooltip('Add project'), findsOneWidget);
    expect((searchRect.top - (sidebarBrandRect.bottom + 1)).abs(), lessThan(1));
  });

  testWidgets(
    'shell renders SessionWorkspaceView when workspace is selected and no active session',
    (tester) async {
      final (controller, fakeService) = await buildController();
      addTearDown(() async {
        await fakeService.shutdown();
      });

      await controller.selectWorkspaceFromPath('/repo');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aleraDatabaseProvider.overrideWith(
              (ref) async => await openMemoryDb(),
            ),
            sessionControllerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(home: AleraShellPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final composerTextField = find.descendant(
        of: find.byType(SessionWorkspaceView),
        matching: find.byType(TextField),
      );

      expect(find.byType(SessionWorkspaceView), findsOneWidget);
      expect(composerTextField, findsOneWidget);
      expect(find.text('Pick a chat'), findsNothing);
    },
  );

  testWidgets(
    'workspace selected keeps full-width chat viewport and centered content',
    (tester) async {
      final (controller, fakeService) = await buildController();
      addTearDown(() async {
        await fakeService.shutdown();
      });
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await controller.selectWorkspaceFromPath('/repo');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aleraDatabaseProvider.overrideWith(
              (ref) async => await openMemoryDb(),
            ),
            sessionControllerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(home: AleraShellPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final workspaceRect = tester.getRect(find.byType(SessionWorkspaceView));
      final scaffoldRect = tester.getRect(find.byType(Scaffold));
      final composerTextField = find.descendant(
        of: find.byType(SessionWorkspaceView),
        matching: find.byType(TextField),
      );
      final textFieldRect = tester.getRect(composerTextField);
      const sidebarWidth = AleraTokens.sidebarDefaultWidth;

      expect(
        (workspaceRect.width - (scaffoldRect.width - sidebarWidth)).abs(),
        lessThan(1.0),
      );
      expect(textFieldRect.width, lessThanOrEqualTo(720));
      final leftGap = textFieldRect.left - workspaceRect.left;
      final rightGap = workspaceRect.right - textFieldRect.right;
      expect((leftGap - rightGap).abs(), lessThan(1.0));
    },
  );

  testWidgets('top and status bars remain full width', (tester) async {
    final (controller, fakeService) = await buildController();
    addTearDown(() async {
      await fakeService.shutdown();
    });
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await controller.selectWorkspaceFromPath('/repo');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraDatabaseProvider.overrideWith(
            (ref) async => await openMemoryDb(),
          ),
          sessionControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: AleraShellPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final scaffoldRect = tester.getRect(find.byType(Scaffold));
    final topBarRect = tester.getRect(find.byType(AleraTopBar));
    final statusBarRect = tester.getRect(find.byType(AleraStatusBar));
    const sidebarWidth = AleraTokens.sidebarDefaultWidth;

    expect(
      (topBarRect.width - (scaffoldRect.width - sidebarWidth)).abs(),
      lessThan(1.0),
    );
    expect(
      (statusBarRect.width - (scaffoldRect.width - sidebarWidth)).abs(),
      lessThan(1.0),
    );
  });

  testWidgets('status bar shows active session workspace path fallback', (
    tester,
  ) async {
    final session = buildSession(
      id: 'session-1',
      workspacePath: '/session-repo',
      title: 'existing session',
    );
    final (controller, fakeService) = await buildController(
      sessions: <AleraSession>[session],
    );
    addTearDown(() async {
      await fakeService.shutdown();
    });

    controller.state = controller.state.copyWith(
      selectedWorkspacePath: '/selected-repo',
      sessions: <AleraSession>[session],
      activeSessionId: session.id,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraDatabaseProvider.overrideWith(
            (ref) async => await openMemoryDb(),
          ),
          sessionControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: AleraShellPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.descendant(
        of: find.byType(AleraStatusBar),
        matching: find.text('/session-repo'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('empty state unchanged when no workspace is selected', (
    tester,
  ) async {
    final (controller, fakeService) = await buildController();
    addTearDown(() async {
      await fakeService.shutdown();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aleraDatabaseProvider.overrideWith(
            (ref) async => await openMemoryDb(),
          ),
          sessionControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: AleraShellPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Pick a chat'), findsOneWidget);
    expect(find.byType(SessionWorkspaceView), findsNothing);
  });
}
