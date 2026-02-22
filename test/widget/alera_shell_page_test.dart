import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_service.dart';
import 'package:alera/src/features/session/presentation/session_workspace_view.dart';
import 'package:alera/src/features/settings/application/settings_service.dart';
import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
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
  }) {
    throw UnimplementedError();
  }

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
  _ShellFakeSettingsService(this._selectedModel, this._selectedReasoningEffort);

  String _selectedModel;
  String _selectedReasoningEffort;

  @override
  Future<SettingsSnapshot> load() async {
    return SettingsSnapshot(
      selectedModel: _selectedModel,
      selectedReasoningEffort: _selectedReasoningEffort,
    );
  }

  @override
  Future<void> save(SettingsSnapshot snapshot) async {
    _selectedModel = snapshot.selectedModel;
    _selectedReasoningEffort = snapshot.selectedReasoningEffort;
  }
}

void main() {
  testWidgets(
    'shell renders SessionWorkspaceView when workspace is selected and no active session',
    (tester) async {
      final fakeService = _ShellFakeSessionService();
      final controller = SessionController(
        sessionService: fakeService,
        projectService: _ShellFakeProjectService(),
        settingsService: _ShellFakeSettingsService('gpt-5.3-codex', 'high'),
      );
      addTearDown(() async {
        await fakeService.shutdown();
      });

      await controller.bootstrap();
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
      expect(find.text('select a repository folder'), findsNothing);
    },
  );
}
