import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/welcome_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDashboard(
    WidgetTester tester, {
    required WorkbenchState state,
    _WelcomeDashboardController? controller,
    Size size = const Size(1200, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workbenchControllerProvider.overrideWith(
            () => controller ?? _WelcomeDashboardController(state),
          ),
          settingsControllerProvider.overrideWith(
            () => _WelcomeDashboardSettingsController(.defaults),
          ),
          agentProfilesProvider.overrideWith(
            () => _WelcomeDashboardAgentProfiles(),
          ),
        ],
        child: const MaterialApp(home: WelcomeDashboard()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'renders the empty dashboard and opens add-project and settings flows',
    (tester) async {
      await pumpDashboard(
        tester,
        state: const WorkbenchState(bootstrapped: true),
        size: const Size(720, 900),
      );

      expect(find.text('Welcome to Alera'), findsOneWidget);
      expect(find.text('Quick Start'), findsOneWidget);
      expect(find.text('Keyboard Shortcuts'), findsOneWidget);
      expect(find.text('Projects & Workspaces'), findsNothing);
      expect(find.text('No Projects Registered Yet'), findsNothing);

      await tester.tap(find.text('Add Project').first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Project Path'), findsOneWidget);
      await tester.tap(find.text('Cancel').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Settings').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Application'), findsWidgets);
    },
  );

  testWidgets('renders quick start and opens the create-workspace flow', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 5, 22);
    final project = Project(
      id: 'project-1',
      name: 'Alera',
      repoPath: '/repo/alera',
      createdAt: now,
      updatedAt: now,
    );
    final workspace = Workspace(
      id: 'workspace-1',
      projectId: project.id,
      name: 'Main',
      branch: 'main',
      path: project.repoPath,
      createdAt: now,
      updatedAt: now,
      kind: .main,
      status: .active,
    );

    final controller = _WelcomeDashboardController(
      WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[workspace],
        },
        activeProjectId: project.id,
        activeWorkspaceId: workspace.id,
        bootstrapped: true,
      ),
    );
    await pumpDashboard(
      tester,
      controller: controller,
      state: WorkbenchState(
        projects: <Project>[project],
        workspacesByProject: <String, List<Workspace>>{
          project.id: <Workspace>[workspace],
        },
        activeProjectId: project.id,
        activeWorkspaceId: workspace.id,
        bootstrapped: true,
      ),
    );

    expect(find.text('Quick Start'), findsOneWidget);
    expect(find.text('Keyboard Shortcuts'), findsOneWidget);
    expect(find.text('Projects & Workspaces'), findsNothing);
    expect(find.text('Main'), findsNothing);

    await tester.tap(find.text('New Workspace').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Manual'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue Manually'));
    await tester.pumpAndSettle();

    // Tap Continue to go to Step 2
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, 'Create Workspace'),
      findsOneWidget,
    );
  });
}

class _WelcomeDashboardAgentProfiles extends AgentProfiles {
  @override
  Future<List<AgentProfile>> build() async => const <AgentProfile>[];
}

class _WelcomeDashboardController(final WorkbenchState _seed)
    extends WorkbenchController {
  @override
  WorkbenchState build() => _seed;

  @override
  Future<void> bootstrap() async {}

  @override
  Future<List<String>> listSourceBranches(Project project) async {
    return const <String>['main'];
  }
}

class _WelcomeDashboardSettingsController(final AleraSettings _seed)
    extends SettingsController {
  @override
  AleraSettings build() => _seed;
}
