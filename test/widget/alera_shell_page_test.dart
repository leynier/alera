import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_service.dart';
import 'package:alera/src/features/session/presentation/session_workspace_view.dart';
import 'package:alera/src/features/settings/application/settings_service.dart';
import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
import 'package:alera/src/features/shell/presentation/alera_status_bar.dart';
import 'package:alera/src/features/shell/presentation/alera_top_bar.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _ShellFakeSessionService implements SessionService {
  final StreamController<SessionRuntimeEvent> _eventsController =
      StreamController<SessionRuntimeEvent>.broadcast();

  @override
  Stream<SessionRuntimeEvent> get events => _eventsController.stream;

  @override
  List<AleraSession> get sessions => const <AleraSession>[];

  @override
  Future<void> ensureConnected() async {}

  @override
  AleraSession? findLatestSessionForWorkspace(String workspacePath) => null;

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
  Future<void> runInput({
    required String sessionId,
    required String rawInput,
    required String reasoningEffort,
    List<Map<String, dynamic>> extraInputItems = const <Map<String, dynamic>>[],
    bool planModeEnabled = false,
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
  Future<AleraSession> setActiveSession(String sessionId) {
    throw UnimplementedError();
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
}

class _ShellFakeProjectService implements ProjectService {
  @override
  Future<bool> isGitRepository(String path) async => true;

  @override
  Future<ProjectValidationResult> validateGitRepository(String path) async {
    return ProjectValidationResult.ok();
  }
}

class _ShellFakeSettingsService implements SettingsService {
  _ShellFakeSettingsService(
    this._selectedModel,
    this._selectedReasoningEffort,
    this._markdownEnabled,
  );

  String _selectedModel;
  String _selectedReasoningEffort;
  bool _markdownEnabled;

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
    _selectedModel = snapshot.selectedModel;
    _selectedReasoningEffort = snapshot.selectedReasoningEffort;
    _markdownEnabled = snapshot.markdownEnabled;
  }
}

void main() {
  Future<(SessionController, _ShellFakeSessionService)>
  buildController() async {
    final fakeService = _ShellFakeSessionService();
    final controller = SessionController(
      sessionService: fakeService,
      projectService: _ShellFakeProjectService(),
      settingsService: _ShellFakeSettingsService('gpt-5.3-codex', 'high', true),
    );
    await controller.bootstrap();
    return (controller, fakeService);
  }

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
            sessionControllerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(home: AleraShellPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SessionWorkspaceView), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Select a repository folder'), findsNothing);
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
            sessionControllerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(home: AleraShellPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final workspaceRect = tester.getRect(find.byType(SessionWorkspaceView));
      final scaffoldRect = tester.getRect(find.byType(Scaffold));
      final textFieldRect = tester.getRect(find.byType(TextField));

      expect((workspaceRect.width - scaffoldRect.width).abs(), lessThan(1.0));
      expect(textFieldRect.width, lessThanOrEqualTo(720));
      final leftGap = textFieldRect.left - scaffoldRect.left;
      final rightGap = scaffoldRect.right - textFieldRect.right;
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

    expect((topBarRect.width - scaffoldRect.width).abs(), lessThan(1.0));
    expect((statusBarRect.width - scaffoldRect.width).abs(), lessThan(1.0));
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
          sessionControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: AleraShellPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Select a repository folder'), findsOneWidget);
    expect(find.byType(SessionWorkspaceView), findsNothing);
  });
}
