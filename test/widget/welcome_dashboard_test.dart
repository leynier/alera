import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'welcome_dashboard_test_support.dart';

void main() {
  final profile = _profile();

  Future<WelcomeDashboardRecordedPrompt> pumpDashboard(
    WidgetTester tester, {
    required WorkbenchState state,
    List<AgentProfile> profiles = const <AgentProfile>[],
    Size size = const Size(1200, 900),
  }) {
    return pumpWelcomeDashboard(
      tester,
      state: state,
      profiles: profiles,
      size: size,
    );
  }

  testWidgets(
    'offers add project and create profile when nothing is configured',
    (tester) async {
      await pumpDashboard(
        tester,
        state: const WorkbenchState(bootstrapped: true),
        size: const Size(1440, 1000),
      );

      expect(find.text('Welcome to Alera'), findsNothing);
      expect(find.text('Quick Start'), findsNothing);
      expect(find.text('What should we build?'), findsOneWidget);
      expect(find.text('No projects yet'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('home-composer-send')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const ValueKey<String>('home-composer-add-project')),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Project Path'), findsOneWidget);
      await tester.tap(find.text('Cancel').first);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('home-composer-create-profile')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Agent Profiles'), findsWidgets);
    },
  );

  testWidgets('shows the composer for a project and an agent profile', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      state: _projectState(),
      profiles: <AgentProfile>[profile],
    );

    expect(find.text('What should we build in '), findsOneWidget);
    expect(find.text('Alera'), findsWidgets);
    expect(find.text('Create a Worktree'), findsNothing);
    expect(find.text('Project Folder'), findsOneWidget);
    expect(find.text('This Device'), findsOneWidget);
    expect(find.text('No Parent'), findsOneWidget);
    expect(find.text(profile.name), findsOneWidget);
    expect(find.text('New Workspace'), findsNothing);
  });

  testWidgets('enqueues a checkout workspace from the prompt', (tester) async {
    final jobs = await pumpDashboard(
      tester,
      state: _projectState(),
      profiles: <AgentProfile>[profile],
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('home-composer-prompt')),
      '  Build the home composer  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('home-composer-send')));
    await tester.pump();

    final request = jobs.request;
    expect(request, isNotNull);
    expect(request!.useProjectCheckout, isTrue);
    expect(request.sourceBranch, isEmpty);
    expect(request.prompt, 'Build the home composer');
    expect(request.profileId, profile.id);
    expect(request.project.id, 'project-1');
    expect(request.hostId, isNull);
    expect(request.parentWorkspaceId, isNull);
    expect(request.autoAssignSection, isFalse);
    expect(find.text('Build the home composer'), findsNothing);
  });

  testWidgets('project folder chip switches to a worktree branch', (
    tester,
  ) async {
    final jobs = await pumpDashboard(
      tester,
      state: _projectState(),
      profiles: <AgentProfile>[profile],
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('home-composer-location')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();

    expect(find.text('From main'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('home-composer-prompt')),
      'Build it on a branch',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('home-composer-send')));
    await tester.pump();

    final request = jobs.request;
    expect(request, isNotNull);
    expect(request!.useProjectCheckout, isFalse);
    expect(request.sourceBranch, 'main');
  });

  testWidgets('a folder project keeps project folder static', (tester) async {
    await pumpDashboard(
      tester,
      state: _projectState(kind: .folder),
      profiles: <AgentProfile>[profile],
    );

    expect(find.text('Project Folder'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('home-composer-location')),
      findsNothing,
    );
  });

  testWidgets('asks for an agent profile when the project has none', (
    tester,
  ) async {
    await pumpDashboard(tester, state: _projectState());

    expect(find.text('No agent profiles'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('home-composer-create-profile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('home-composer-send')),
      findsNothing,
    );
  });

  testWidgets('switches the heading when another project is picked', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 5, 22);
    final other = Project(
      id: 'project-2',
      name: 'Other',
      repoPath: '/repo/other',
      createdAt: now,
      updatedAt: now,
    );
    final state = _projectState();
    await pumpDashboard(
      tester,
      state: state.copyWith(projects: <Project>[...state.projects, other]),
      profiles: <AgentProfile>[profile],
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('home-composer-project')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();

    expect(find.text('Other'), findsWidgets);
    expect(find.text('Alera'), findsNothing);
  });
}

AgentProfile _profile() => welcomeDashboardProfile();

WorkbenchState _projectState({ProjectKind kind = ProjectKind.gitRepository}) {
  return welcomeDashboardProjectState(kind: kind);
}
