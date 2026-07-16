import 'dart:async';

import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/presentation/workspace_pull_requests_panel.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_forge_provider.dart';
import '../unit/fake_git_backend.dart';

HostedReview _review(int number) => HostedReview(
  provider: GitHostingProvider.github,
  number: number,
  title: 'feat: $number',
  state: HostedReviewState.open,
  url: 'https://github.com/leynier/alera/pull/$number',
  author: 'leynier',
  baseBranch: 'main',
  headBranch: 'feature',
);

class _PanelWorkbenchController extends WorkbenchController {
  @override
  WorkbenchState build() => const WorkbenchState();
}

void main() {
  testWidgets('keeps the review visible while Refresh shows loading', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 7, 16);
    final workspace = Workspace(
      id: 'workspace-1',
      projectId: 'project-1',
      name: 'Feature',
      branch: 'feature',
      path: '/repo',
      createdAt: now,
      updatedAt: now,
      kind: WorkspaceKind.linked,
      status: WorkspaceStatus.active,
    );
    final forge = FakeForgeProvider()..branchReview = _review(123);
    final git = FakeGitBackend()
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      };
    var panelVisible = true;
    late StateSetter setHostState;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          effectiveHostingProviderOverrideProvider.overrideWith(
            (ref, projectId) async => null,
          ),
          gitBackendProvider.overrideWithValue(git),
          forgeProviderRegistryProvider.overrideWithValue(
            ForgeProviderRegistry(<ForgeProvider>[forge]),
          ),
          linkedReviewRepositoryProvider.overrideWithValue(
            FakeLinkedReviewRepository(),
          ),
          workbenchControllerProvider.overrideWith(
            _PanelWorkbenchController.new,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                return SizedBox(
                  width: 360,
                  height: 640,
                  child: panelVisible
                      ? WorkspacePullRequestsPanel(
                          workspace: workspace,
                          repoPath: workspace.path,
                        )
                      : const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('feat: 123'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);

    final gate = Completer<HostedReview?>();
    forge.branchReviewLoader = () => gate.future;
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();

    expect(find.text('feat: 123'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsNothing);

    gate.complete(_review(456));
    await tester.pumpAndSettle();

    expect(find.text('feat: 456'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);

    setHostState(() => panelVisible = false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 121));
    expect(forge.branchReviewCalls, 2);

    final resumeGate = Completer<HostedReview?>();
    forge.branchReviewLoader = () => resumeGate.future;
    setHostState(() => panelVisible = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('feat: 456'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(forge.branchReviewCalls, 3);

    resumeGate.complete(_review(789));
    await tester.pumpAndSettle();
    expect(find.text('feat: 789'), findsOneWidget);
  });
}
