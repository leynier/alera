import 'dart:async';

import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/projects/application/project_hosts_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/presentation/welcome_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'welcome_dashboard_test_support.dart';

void main() {
  final profile = welcomeDashboardProfile();

  testWidgets('project folder stays reachable while branches reload', (
    tester,
  ) async {
    final state = welcomeDashboardProjectState();
    final branches = WelcomeDashboardBranchSource();
    final jobs = await pumpWelcomeDashboard(
      tester,
      state: state,
      profiles: <AgentProfile>[profile],
      controller: WelcomeDashboardTestController(state, branches: branches),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('home-composer-location')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    expect(find.text('From main'), findsOneWidget);

    final hang = Completer<List<String>>();
    addTearDown(() {
      if (!hang.isCompleted) {
        hang.complete(const <String>['develop']);
      }
    });
    branches.hang = hang;
    await tester.tap(find.byKey(const ValueKey<String>('home-composer-host')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This Device').last);
    await tester.pump();
    expect(find.text('Loading Branches'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('home-composer-location')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project Folder').last);
    await tester.pump();
    expect(find.text('Project Folder'), findsWidgets);
    expect(find.text('From develop'), findsNothing);

    hang.complete(const <String>['develop']);
    await tester.pumpAndSettle();
    expect(find.text('From develop'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey<String>('home-composer-prompt')),
      'Stay in the folder',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('home-composer-send')));
    await tester.pump();
    expect(jobs.request, isNotNull);
    expect(jobs.request!.useProjectCheckout, isTrue);
    expect(jobs.request!.sourceBranch, isEmpty);
  });

  testWidgets('a host change drops a project folder catalog still loading', (
    tester,
  ) async {
    final state = welcomeDashboardProjectState();
    final branches = WelcomeDashboardBranchSource();
    final hang = Completer<List<String>>();
    addTearDown(() {
      if (!hang.isCompleted) {
        hang.complete(const <String>['develop']);
      }
    });
    branches.hang = hang;
    await pumpWelcomeDashboard(
      tester,
      state: state,
      profiles: <AgentProfile>[profile],
      controller: WelcomeDashboardTestController(state, branches: branches),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('home-composer-location')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('home-composer-host')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This Device').last);
    await tester.pump();

    hang.completeError(Exception('branch catalog failed'));
    await tester.pumpAndSettle();
    expect(find.text('branch catalog failed'), findsNothing);
    expect(find.text('Loading Branches'), findsNothing);
    // The original tap still opens its menu once the stale load returns.
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    branches.hang = null;
    await tester.tap(
      find.byKey(const ValueKey<String>('home-composer-location')),
    );
    await tester.pumpAndSettle();
    expect(find.text('main'), findsOneWidget);
  });

  testWidgets('a catalog error clears when the project changes', (
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
    final base = welcomeDashboardProjectState();
    final state = base.copyWith(projects: <Project>[...base.projects, other]);
    final branches = WelcomeDashboardBranchSource();
    await pumpWelcomeDashboard(
      tester,
      state: state,
      profiles: <AgentProfile>[profile],
      controller: WelcomeDashboardTestController(state, branches: branches),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('home-composer-location')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    branches.error = Exception('branch catalog failed');
    await tester.tap(find.byKey(const ValueKey<String>('home-composer-host')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This Device').last);
    await tester.pumpAndSettle();
    expect(find.text('branch catalog failed'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('home-composer-project')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    expect(find.text('branch catalog failed'), findsNothing);
  });

  testWidgets('a successful branch reload clears the catalog error', (
    tester,
  ) async {
    final state = welcomeDashboardProjectState();
    final branches = WelcomeDashboardBranchSource();
    await pumpWelcomeDashboard(
      tester,
      state: state,
      profiles: <AgentProfile>[profile],
      controller: WelcomeDashboardTestController(state, branches: branches),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('home-composer-location')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('main'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('home-composer-prompt')),
      'Retry the branch',
    );
    await tester.pump();

    branches.error = Exception('branch catalog failed');
    await tester.tap(find.byKey(const ValueKey<String>('home-composer-host')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This Device').last);
    await tester.pumpAndSettle();
    expect(find.text('branch catalog failed'), findsOneWidget);
    expect(
      tester
          .widget<AleraIconButton>(
            find.byKey(const ValueKey<String>('home-composer-send')),
          )
          .onPressed,
      isNull,
    );

    branches.error = null;
    await tester.tap(
      find.byKey(const ValueKey<String>('home-composer-location')),
    );
    await tester.pumpAndSettle();
    expect(find.text('branch catalog failed'), findsNothing);
    expect(find.text('From main'), findsOneWidget);
    expect(
      tester
          .widget<AleraIconButton>(
            find.byKey(const ValueKey<String>('home-composer-send')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('a remote host is not missing while ssh targets are loading', (
    tester,
  ) async {
    final pending = StreamController<List<SshTarget>>();
    addTearDown(pending.close);
    final jobs = await pumpWelcomeDashboard(
      tester,
      state: welcomeDashboardRemoteState(),
      profiles: <AgentProfile>[profile],
      extraOverrides: <Override>[
        sshTargetsProvider.overrideWith((ref) => pending.stream),
      ],
    );

    expect(find.textContaining('ssh target not found'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey<String>('home-composer-prompt')),
      'Build remotely',
    );
    await tester.pump();
    expect(
      tester
          .widget<AleraIconButton>(
            find.byKey(const ValueKey<String>('home-composer-send')),
          )
          .onPressed,
      isNull,
    );

    pending.add(<SshTarget>[welcomeDashboardSshTarget()]);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('ssh target not found'), findsNothing);
    expect(find.text('Build Box'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('home-composer-send')));
    await tester.pump();
    expect(jobs.request, isNotNull);
    expect(jobs.request!.hostId, 'ssh-win');
    expect(jobs.request!.useProjectCheckout, isTrue);
  });

  testWidgets('host support flipping keeps the add-to-host path', (
    tester,
  ) async {
    final jobs = await pumpWelcomeDashboard(
      tester,
      state: welcomeDashboardProjectState(),
      profiles: <AgentProfile>[profile],
      extraOverrides: <Override>[
        projectHostsSupportedProvider.overrideWith(
          (ref) => ref.watch(welcomeDashboardHostSupportProvider),
        ),
        sshTargetsProvider.overrideWith(
          (ref) => Stream.value(<SshTarget>[welcomeDashboardSshTarget()]),
        ),
      ],
    );
    await tester.tap(find.byKey(const ValueKey<String>('home-composer-host')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build Box'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not on'), findsOneWidget);
    expect(find.text('Add to Host'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Existing Path'),
      '/kept',
    );
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WelcomeDashboard)),
    );
    container.read(welcomeDashboardHostSupportProvider.notifier).set(false);
    await tester.pump();
    await tester.pump();
    container.read(welcomeDashboardHostSupportProvider.notifier).set(true);
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(TextField, 'Existing Path'), findsOneWidget);
    expect(find.text('/kept'), findsOneWidget);
    expect(jobs.request, isNull);
  });

  testWidgets('a long worktree branch ellipsizes in the location chip', (
    tester,
  ) async {
    const branch = 'feature/home-composer-location-chip-should-ellipsis';
    final state = welcomeDashboardProjectState();
    final branches = WelcomeDashboardBranchSource()
      ..names = const <String>[branch];
    await pumpWelcomeDashboard(
      tester,
      state: state,
      size: const Size(390, 760),
      profiles: <AgentProfile>[profile],
      controller: WelcomeDashboardTestController(state, branches: branches),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('home-composer-location')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(branch));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('From $branch'), findsOneWidget);
    expect(find.text('This Device'), findsOneWidget);
  });
}
