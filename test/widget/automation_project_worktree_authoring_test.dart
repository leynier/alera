import 'package:alera/src/features/automations/application/automation_project_branches.dart';
import 'package:alera/src/features/automations/application/automation_workspace_tags.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/presentation/authoring/automation_prompt_editor.dart';
import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/automation_test_harness.dart';

void main() {
  Future<FakeAutomationRuntime> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final runtime = FakeAutomationRuntime();
    final container = automationContainer(
      runtime,
      overrides: [
        automationWorkspaceTagsProvider.overrideWith(
          (ref) async => <WorkspaceTag>[
            WorkspaceTag(
              id: 'tag-1',
              name: 'Triage',
              createdAt: DateTime.utc(2026, 10),
              updatedAt: DateTime.utc(2026, 10),
            ),
          ],
        ),
        automationProjectBranchesProvider.overrideWith(
          (ref, projectId) async =>
              (branches: const <String>['main', 'develop'], initial: 'develop'),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(runtime.dispose);
    await tester.pumpWidget(AutomationsTestApp(container: container));
    container
        .read(automationsNavigationProvider.notifier)
        .startAuthoring(const AutomationAuthoringRequest());
    await tester.pumpAndSettle();
    return runtime;
  }

  Finder promptField() => find.descendant(
    of: find.byType(AutomationPromptEditor),
    matching: find.byType(TextField),
  );

  testWidgets('typing {{ offers variables and Tab inserts one', (tester) async {
    await open(tester);
    await tester.enterText(promptField(), 'Check {{run.n');
    await tester.pumpAndSettle();
    expect(find.text('{{run.number}}'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(promptField()).controller!.text,
      'Check {{run.number}}',
    );
    expect(find.text('Tab or Enter inserts. Esc closes.'), findsNothing);
  });

  testWidgets('a chip inserts its variable at the caret', (tester) async {
    await open(tester);
    await tester.enterText(promptField(), 'Review ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project Name'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(promptField()).controller!.text,
      'Review {{project.name}}',
    );
  });

  testWidgets('a project worktree target sends the project and branch', (
    tester,
  ) async {
    final runtime = await open(tester);
    await tester.enterText(promptField(), 'Review open work');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Worktree From A Project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alera').last);
    await tester.pumpAndSettle();
    expect(find.text('develop'), findsOneWidget);
    await tester.ensureVisible(find.text('Triage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Triage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Automation'));
    await tester.pumpAndSettle();
    final sent =
        runtime.requestsOf('automation.create').single.payload['automation']!
            as Map<String, Object?>;
    expect(sent['projectId'], 'project-1');
    expect(sent['target'], <String, Object?>{
      'projectWorktree': <String, Object?>{
        'projectId': 'project-1',
        'sourceBranch': 'develop',
        'nameTemplate': 'auto-{{automation.slug}}-{{run.number}}',
        'agentProfileId': 'codex',
      },
    });
    expect(sent['workspacePlacement'], <String, Object?>{
      'tagIds': <String>['tag-1'],
    });
  });
}
