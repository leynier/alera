import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/forge_stack_provider.dart';
import 'package:alera/src/features/pull_requests/application/pull_request_providers.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/presentation/workspace_pull_requests_panel.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_forge_provider.dart';
import '../unit/fake_git_backend.dart';

class _StackPanelWorkbenchController(final WorkbenchState initialState)
    extends WorkbenchController {
  @override
  WorkbenchState build() => initialState;
}

class _StackPanelForgeProvider extends FakeForgeProvider
    implements ForgeStackProvider {
  @override
  Future<HostedReviewStack?> getStackForReview({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int reviewNumber,
  }) async => null;

  @override
  Future<HostedReviewStack> linkReviewStack({
    required GitRemoteIdentity identity,
    required String repoPath,
    required List<int> reviewNumbers,
    int? stackNumber,
    String? baseBranch,
  }) => throw UnimplementedError();

  @override
  Future<void> mergeReviewStack({
    required GitRemoteIdentity identity,
    required String repoPath,
    required int reviewNumber,
    required ReviewMergeMethod method,
  }) => throw UnimplementedError();
}

void main() {
  testWidgets('creates a stack from workspaces before the current PR exists', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 8, 16);
    final project = Project(
      id: 'project-1',
      name: 'Alera',
      repoPath: '/repo',
      createdAt: now,
      updatedAt: now,
    );
    final first = Workspace(
      id: 'workspace-one',
      projectId: project.id,
      name: 'Workspace One',
      branch: 'feature/one',
      path: '/repo-one',
      createdAt: now,
      updatedAt: now,
      kind: .linked,
      status: .active,
      sourceBranch: 'main',
    );
    final current = Workspace(
      id: 'workspace-two',
      projectId: project.id,
      name: 'Workspace Two',
      branch: 'feature/two',
      path: '/repo-two',
      createdAt: now,
      updatedAt: now,
      kind: .linked,
      status: .active,
      sourceBranch: first.branch,
      parentWorkspaceId: first.id,
    );
    final forge = _StackPanelForgeProvider();
    final git = FakeGitBackend()
      ..headBranch = 'feature/two'
      ..sourceBranches = <String>['main', 'feature/one', 'feature/two']
      ..remotesByName = <String, String?>{
        'origin': 'https://github.com/leynier/alera.git',
      };
    final workbenchState = WorkbenchState(
      projects: <Project>[project],
      workspacesByProject: <String, List<Workspace>>{
        project.id: <Workspace>[first, current],
      },
      activeProjectId: project.id,
      activeWorkspaceId: current.id,
    );

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
          settingsControllerProvider.overrideWithValue(.defaults),
          workbenchControllerProvider.overrideWith(
            () => _StackPanelWorkbenchController(workbenchState),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 720,
              child: WorkspacePullRequestsPanel(
                workspace: current,
                repoPath: current.path,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create Stack'), findsOneWidget);
    await tester.tap(find.text('Create Stack'));
    await tester.pumpAndSettle();

    expect(find.text('Create Stack From Workspaces'), findsOneWidget);
    expect(find.text('1. Workspace One'), findsOneWidget);
  });
}
