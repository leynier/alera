import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/home_composer_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'welcome_dashboard_test_support.dart';

void main() {
  final profile = welcomeDashboardProfile();

  WorkbenchState twoProjects({HomeComposerPrefs? saved}) {
    final state = welcomeDashboardProjectState();
    final now = DateTime.utc(2026, 5, 22);
    return state.copyWith(
      projects: <Project>[
        ...state.projects,
        Project(
          id: 'project-2',
          name: 'Other',
          repoPath: '/repo/other',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      viewPrefs: saved == null
          ? state.viewPrefs
          : state.viewPrefs.copyWith(homeComposer: saved),
    );
  }

  Future<void> pick(WidgetTester tester, String key, String label) async {
    await tester.tap(find.byKey(ValueKey<String>('home-composer-$key')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('Home composer choices are saved to the view prefs', (
    tester,
  ) async {
    final state = twoProjects();
    final branches = WelcomeDashboardBranchSource()
      ..names = const ['main', 'develop'];
    final controller = WelcomeDashboardTestController(
      state,
      branches: branches,
    );
    await pumpWelcomeDashboard(
      tester,
      state: state,
      profiles: [profile],
      controller: controller,
    );

    await pick(tester, 'location', 'New Worktree');
    await pick(tester, 'source', 'develop');
    await pick(tester, 'profile', profile.name);

    final saved = controller.state.viewPrefs.homeComposer;
    expect(saved.profileId, profile.id);
    final project = saved.projects['project-1']!;
    expect(project.useProjectCheckout, isFalse);
    expect(project.sourceBranch, 'develop');
    expect(project.hostId, isNull);

    await pick(tester, 'project', 'Other');
    expect(controller.state.viewPrefs.homeComposer.projectId, 'project-2');
  });

  testWidgets('Home composer restores the saved project', (tester) async {
    await pumpWelcomeDashboard(
      tester,
      state: twoProjects(
        saved: const HomeComposerPrefs(projectId: 'project-2'),
      ),
      profiles: [profile],
    );

    expect(find.text('Other'), findsWidgets);
    expect(find.text('Alera'), findsNothing);
  });

  testWidgets('Home composer restores a saved worktree and branch', (
    tester,
  ) async {
    final state = twoProjects(
      saved: const HomeComposerPrefs(
        projects: <String, HomeComposerProjectPrefs>{
          'project-1': HomeComposerProjectPrefs(
            useProjectCheckout: false,
            sourceBranch: 'develop',
          ),
        },
      ),
    );
    final branches = WelcomeDashboardBranchSource()
      ..names = const ['main', 'develop'];
    await pumpWelcomeDashboard(
      tester,
      state: state,
      profiles: [profile],
      controller: WelcomeDashboardTestController(state, branches: branches),
    );

    expect(find.text('New Worktree'), findsOneWidget);
    expect(find.text('From develop'), findsOneWidget);
  });

  testWidgets('a saved branch that no longer exists falls back to main', (
    tester,
  ) async {
    final state = twoProjects(
      saved: const HomeComposerPrefs(
        projects: <String, HomeComposerProjectPrefs>{
          'project-1': HomeComposerProjectPrefs(
            useProjectCheckout: false,
            sourceBranch: 'deleted',
          ),
        },
      ),
    );
    final branches = WelcomeDashboardBranchSource()
      ..names = const ['main', 'develop'];
    await pumpWelcomeDashboard(
      tester,
      state: state,
      profiles: [profile],
      controller: WelcomeDashboardTestController(state, branches: branches),
    );

    expect(find.text('From main'), findsOneWidget);
  });
}
