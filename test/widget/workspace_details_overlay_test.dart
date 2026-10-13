import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';
import 'package:alera/src/features/pull_requests/domain/review_action_access.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_review_row.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_state.dart';

import 'dart:convert';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_details_card.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/domain/workspace_pull_request_scope.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_details_provider.dart';
import 'package:alera/src/features/workbench/application/workspace_source_control_controller.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_git_quick_action.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/terminal_surface_toolbar.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/presentation/workspace_details_overlay.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_workspace_comparison.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

part 'workspace_details_controls_test_cases.dart';

class _Workbench extends WorkbenchController {
  @override
  WorkbenchState build() => const WorkbenchState(activeWorkspaceId: 'w');
  @override
  void setRightSidebarVisible(bool visible) => state = state.copyWith(
    viewPrefs: state.viewPrefs.copyWith(rightSidebarVisible: visible),
  );
  @override
  void setContextPanelTab(WorkbenchContextPanelTab tab) =>
      state = state.copyWith(
        viewPrefs: state.viewPrefs.copyWith(activeContextPanelTab: tab),
      );
  @override
  void toggleWorkspaceDetails(String id) {
    final hidden = {...state.viewPrefs.workspaceDetailsHiddenIds};
    if (!hidden.add(id)) hidden.remove(id);
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(workspaceDetailsHiddenIds: hidden),
    );
  }
}

class _Reviews extends WorkspacePullRequestController {
  _Reviews(this.snapshot);
  final WorkspacePullRequestState snapshot;
  @override
  Future<WorkspacePullRequestState> build(
    WorkspacePullRequestScope scope,
  ) async => snapshot;
  @override
  void attachPanel() {}
  @override
  void detachPanel() {}
}

class _Sources extends WorkspaceSourceControlController {
  @override
  Future<WorkspaceSourceControlState> build(String workspacePath) async =>
      details.sourceControl;
}

class _Runtime implements TerminalRuntime {
  @override
  TerminalSessionHandle? peekSession(String tabId) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final workspace = Workspace(
  id: 'w',
  projectId: 'p',
  name: 'Details',
  path: '/repo',
  branch: 'feature/details',
  sourceBranch: 'main',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  kind: WorkspaceKind.linked,
  status: WorkspaceStatus.active,
);
const scope = WorkspacePullRequestScope(
  workspaceId: 'w',
  repoPath: '/repo',
  branch: 'feature/details',
  sourceBranch: 'main',
);
const comparison = GitWorkspaceComparison(
  baseRef: 'origin/main',
  baseOid: 'base',
  headOid: 'head',
  headRef: 'refs/heads/feature/details',
  treeOid: 'tree',
  indexOid: 'index',
  entries: [],
  added: 42,
  removed: 8,
);
final details = WorkspaceDetailsState(
  sourceControl: const WorkspaceSourceControlState(
    status: GitStatusResult(entries: []),
    repositoryState: GitRepositoryState(branch: 'feature/details'),
    stashes: [],
  ),
  comparison: comparison,
  branches: ['main', 'feature/details'],
  defaultBranch: 'main',
  quickAction: const WorkspaceGitQuickActionState(
    action: WorkspaceGitQuickAction.commitPush,
  ),
  pullRequest: null,
  hasRemote: true,
);
Future<void> pumpOverlay(
  WidgetTester tester,
  Size size, {
  Widget? child,
  Future<WorkspaceDetailsState> Function()? loadDetails,
  WorkspacePullRequestState reviewState = const WorkspacePullRequestState(),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workbenchControllerProvider.overrideWith(_Workbench.new),
        terminalRuntimeProvider.overrideWithValue(_Runtime()),
        workspaceSourceControlControllerProvider('/repo')
            .overrideWith(_Sources.new),
        sshTargetsProvider.overrideWith(
          (ref) => Stream.value(const <SshTarget>[]),
        ),
        effectiveHostingProviderOverrideProvider('p')
            .overrideWith((ref) async => null),
        workspacePullRequestControllerProvider(scope)
            .overrideWith(() => _Reviews(reviewState)),
        workspaceDetailsProvider(scope)
            .overrideWith((ref) async => await loadDetails?.call() ?? details),
      ],
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: WorkspaceDetailsOverlay(
            workspace: workspace,
            sourceControlScope: const WorkspaceSourceControlScope(
              workspaceId: 'w',
              workspacePath: '/repo',
              path: '/repo',
            ),
            child: child ?? const SizedBox.expand(key: Key('terminal-area')),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final entry in manifest) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in entry['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  _registerWorkspaceDetailsControlTests();

  testWidgets('current PR stays first and stack expands without duplicates', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const current = HostedReview(
      provider: .github,
      number: 123,
      title: 'Details',
      state: .open,
      url: 'https://github.com/a/b/pull/123',
      baseBranch: 'main',
      headBranch: 'feature/details',
      mergeable: .mergeable,
    );
    final other = current.copyWith(
      number: 122,
      title: 'Base Layer',
      state: .merged,
    );
    await pumpOverlay(
      tester,
      const Size(1000, 700),
      reviewState: WorkspacePullRequestState(
        review: current,
        authStatus: .authenticated,
        checksLoaded: true,
        actionAccess: const ReviewActionAccess(canMerge: true),
        mergeMethods: const [.squash],
        stackChecksLoaded: true,
        stack: HostedReviewStack(
          number: 7,
          baseBranch: 'main',
          open: true,
          entries: [
            HostedReviewStackEntry(review: other, position: 1),
            const HostedReviewStackEntry(review: current, position: 2),
          ],
        ),
      ),
    );
    expect(find.text('#123: Details'), findsOneWidget);
    expect(find.text('#122: Base Layer'), findsNothing);
    expect(
      tester.getTopLeft(find.text('#123: Details')).dy,
      greaterThan(tester.getTopLeft(find.text('feature/details')).dy),
    );
    await tester.tap(find.text('Show Stack (1)'));
    await tester.pumpAndSettle();
    expect(find.text('#123: Details'), findsOneWidget);
    expect(find.text('#122: Base Layer'), findsOneWidget);
    expect(find.text('Merge'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'essential density retains PR and changes and exposes workspace options',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpOverlay(tester, const Size(1000, 290));
      expect(find.byTooltip('Workspace Options'), findsOneWidget);
      expect(find.text('Changes'), findsOneWidget);
      expect(find.text('Open In File Manager'), findsNothing);
      await tester.tap(find.byTooltip('Workspace Options'));
      await tester.pumpAndSettle();
      expect(find.text('Host And Hand Off'), findsOneWidget);
      expect(find.text('Open In'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opening the popup preserves the focused terminal surface', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final terminalFocus = FocusNode();
    addTearDown(terminalFocus.dispose);
    await pumpOverlay(
      tester,
      const Size(400, 400),
      child: Focus(
        focusNode: terminalFocus,
        autofocus: true,
        child: const SizedBox.expand(),
      ),
    );
    expect(terminalFocus.hasFocus, isTrue);
    await tester.tap(find.byTooltip('Toggle Workspace Details'));
    await tester.pumpAndSettle();
    expect(find.text('Changes'), findsOneWidget);
    expect(terminalFocus.hasFocus, isTrue);
  });
  testWidgets('short windows keep lower actions available by scrolling', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOverlay(tester, const Size(400, 140));
    await tester.tap(find.byTooltip('Toggle Workspace Details'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Changes'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Changes'), findsOneWidget);
  });
  testWidgets(
    'wide card preserves terminal dimensions when hidden and restored',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpOverlay(tester, const Size(1120, 720));
      expect(find.text('feature/details'), findsOneWidget);
      expect(find.text('+42'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('terminal-area'))),
        const Size(1120, 720),
      );
      await tester.tap(find.byTooltip('Toggle Workspace Details'));
      await tester.pumpAndSettle();
      expect(find.text('Changes'), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('terminal-area'))),
        const Size(1120, 720),
      );
      await tester.tap(find.byTooltip('Toggle Workspace Details'));
      await tester.pumpAndSettle();
      expect(find.text('Changes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'narrow popup starts closed and opens outside a small central pane',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpOverlay(tester, const Size(320, 480));
      expect(find.text('Changes'), findsNothing);
      await tester.tap(find.byTooltip('Toggle Workspace Details'));
      await tester.pumpAndSettle();
      expect(find.text('Changes'), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Changes'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final (os, label) in [
    (HostOs.linux, 'File Manager'),
    (HostOs.macos, 'Finder'),
    (HostOs.windows, 'Explorer'),
  ]) {
    testWidgets('card remains readable with ${os.label} controls', (
      tester,
    ) async {
      for (final (name, asset) in [
        ('Inter', 'assets/fonts/Inter-Variable.ttf'),
        ('JetBrains Mono', 'assets/fonts/JetBrainsMono-Variable.ttf'),
      ]) {
        final loader = FontLoader(name)..addFont(rootBundle.load(asset));
        await loader.load();
      }
      final capture = GlobalKey();
      void action() {}
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: capture,
                child: SizedBox(
                  width: AleraTokens.workspaceDetailsWidth,
                  child: AleraWorkspaceDetailsCard(
                    afterBranch: AleraWorkspaceReviewRow(
                      label: '#123: Add Workspace Details',
                      stateLabel: 'Open',
                      stateIcon: AleraIcons.gitPullRequest,
                      stateColor: AleraTokens.success,
                      tooltip:
                          'feature/workspace-details → main\n2 checks passed',
                      onOpen: action,
                      onMenu: (_) => action(),
                      checksLabel: '2 Checks',
                      checksIcon: AleraIcons.success,
                      checksColor: AleraTokens.success,
                      onChecks: action,
                      actionLabel: 'Merge',
                      onAction: action,
                    ),
                    rows: [
                      AleraWorkspaceDetailRow(
                        label: 'leynier-minipc',
                        leading: AleraHostOsIcon(os: os),
                        onPressed: action,
                        onMenu: (_) => action(),
                      ),
                      AleraWorkspaceDetailRow(
                        label: 'Open In $label',
                        leading: const Icon(
                          AleraIcons.folder,
                          size: AleraTokens.iconMd,
                        ),
                        onPressed: action,
                        onMenu: (_) => action(),
                      ),
                      AleraWorkspaceDetailRow(
                        label: 'feature/workspace-details',
                        subtitle: 'Compare against origin/main',
                        leading: const Icon(
                          AleraIcons.gitBranch,
                          size: AleraTokens.iconMd,
                        ),
                        onPressed: action,
                        onMenu: (_) => action(),
                      ),
                      AleraWorkspaceDetailRow(
                        label: 'Commit, Push & Create PR',
                        leading: const Icon(
                          AleraIcons.gitPush,
                          size: AleraTokens.iconMd,
                        ),
                        onPressed: action,
                        onMenu: (_) => action(),
                      ),
                      AleraWorkspaceDetailRow(
                        label: 'Changes',
                        leading: const Icon(
                          AleraIcons.diff,
                          size: AleraTokens.iconMd,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '+42',
                              style: AleraTokens.statusBarTextStyle.copyWith(
                                color: AleraTokens.success,
                              ),
                            ),
                            const SizedBox(width: AleraTokens.space8),
                            Text(
                              '-8',
                              style: AleraTokens.statusBarTextStyle.copyWith(
                                color: AleraTokens.error,
                              ),
                            ),
                          ],
                        ),
                        onPressed: action,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Open In $label'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['ALERA_VISUAL_REVIEW_DIR'];
      if (directory != null) {
        await tester.runAsync(() async {
          final image =
              await (capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File('$directory/workspace-details-${os.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
