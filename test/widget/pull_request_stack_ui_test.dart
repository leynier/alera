import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review_stack.dart';
import 'package:alera/src/features/pull_requests/domain/review_check_details.dart';
import 'package:alera/src/features/pull_requests/domain/review_merge_method.dart';
import 'package:alera/src/features/pull_requests/domain/review_stack_workspace_models.dart';
import 'package:alera/src/features/pull_requests/domain/update_review_result.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_review_view.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_stack_link_dialog.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _firstReview = HostedReview(
  provider: GitHostingProvider.github,
  number: 41,
  title: 'feat: first layer',
  state: HostedReviewState.open,
  url: 'https://github.com/leynier/alera/pull/41',
  baseBranch: 'main',
  headBranch: 'feature/one',
);

const _currentReview = HostedReview(
  provider: GitHostingProvider.github,
  number: 42,
  title: 'feat: second layer',
  state: HostedReviewState.open,
  url: 'https://github.com/leynier/alera/pull/42',
  baseBranch: 'feature/one',
  headBranch: 'feature/two',
);

const _stack = HostedReviewStack(
  number: 700,
  baseBranch: 'main',
  open: true,
  entries: <HostedReviewStackEntry>[
    HostedReviewStackEntry(review: _firstReview, position: 1),
    HostedReviewStackEntry(review: _currentReview, position: 2),
  ],
);

Widget _reviewView({
  Future<void> Function(ReviewMergeMethod method)? onMerge,
  Future<void> Function(List<int> reviewNumbers)? onLinkStack,
  List<ReviewStackWorkspaceCandidate> stackWorkspaceCandidates =
      const <ReviewStackWorkspaceCandidate>[],
  Future<void> Function(ReviewStackWorkspaceRequest request)?
  onCreateStackFromWorkspaces,
  Set<String> localWorkspaceBranches = const <String>{},
  Future<void> Function(String branch)? onOpenWorkspaceBranch,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PullRequestReviewView(
        review: _currentReview,
        stack: _stack,
        stackSupported: true,
        localWorkspaceBranches: localWorkspaceBranches,
        stackWorkspaceCandidates: stackWorkspaceCandidates,
        checks: const [],
        comments: const [],
        baseBranches: const <String>['main', 'feature/one'],
        mergeMethods: const <ReviewMergeMethod>[ReviewMergeMethod.mergeCommit],
        canCloseReview: true,
        canChangeDraftStatus: true,
        canComment: false,
        action: null,
        onOpenUrl: (_) async {},
        onOpenWorkspaceBranch: onOpenWorkspaceBranch,
        onUnlink: () async {},
        onLinkStack: onLinkStack ?? (_) async {},
        onCreateStackFromWorkspaces:
            onCreateStackFromWorkspaces ?? (_) async {},
        onMerge: onMerge ?? (_) async {},
        onClose: () async {},
        onDraftStatusChanged: (_) async {},
        onAddComment: (_) async => true,
        onUpdate: (_) async => const UpdateReviewSuccess(_currentReview),
        onLoadCheckDetails: (_) async => const ReviewCheckDetails(),
      ),
    ),
  );
}

void main() {
  testWidgets('renders stack order and stack-aware merge action', (
    tester,
  ) async {
    ReviewMergeMethod? mergedWith;
    await tester.pumpWidget(
      _reviewView(onMerge: (method) async => mergedWith = method),
    );

    expect(find.text('Stack #700'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('#41 feat: first layer'), findsOneWidget);
    expect(find.text('#42 feat: second layer'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Create Merge Commit Stack Through #42'), findsOneWidget);

    await tester.tap(find.text('Create Merge Commit Stack Through #42'));
    await tester.pumpAndSettle();

    expect(find.text('Create Merge Commit Stack Through #42?'), findsOneWidget);
    expect(
      find.textContaining('merge 2 pull requests atomically through #42'),
      findsOneWidget,
    );
    expect(mergedWith, isNull);

    await tester.tap(find.text('Create Merge Commit Stack'));
    await tester.pumpAndSettle();
    expect(mergedWith, ReviewMergeMethod.mergeCommit);
  });

  testWidgets('opens the local workspace for another stack layer', (
    tester,
  ) async {
    String? openedBranch;
    await tester.pumpWidget(
      _reviewView(
        localWorkspaceBranches: const <String>{'feature/one'},
        onOpenWorkspaceBranch: (branch) async => openedBranch = branch,
      ),
    );

    expect(find.byTooltip('Open Workspace'), findsOneWidget);
    await tester.tap(find.byTooltip('Open Workspace'));
    await tester.pump();

    expect(openedBranch, 'feature/one');
  });

  testWidgets('opens the workspace stack flow from an existing stack', (
    tester,
  ) async {
    ReviewStackWorkspaceRequest? request;
    await tester.pumpWidget(
      _reviewView(
        stackWorkspaceCandidates: const <ReviewStackWorkspaceCandidate>[
          ReviewStackWorkspaceCandidate(
            workspaceId: 'workspace-one',
            name: 'Workspace One',
            repoPath: '/repo-one',
            branch: 'feature/one',
            current: false,
          ),
          ReviewStackWorkspaceCandidate(
            workspaceId: 'workspace-two',
            name: 'Workspace Two',
            repoPath: '/repo-two',
            branch: 'feature/two',
            current: true,
          ),
          ReviewStackWorkspaceCandidate(
            workspaceId: 'workspace-three',
            name: 'Workspace Three',
            repoPath: '/repo-three',
            branch: 'feature/three',
            current: false,
          ),
        ],
        onCreateStackFromWorkspaces: (value) async => request = value,
      ),
    );

    expect(find.text('Add Workspaces'), findsOneWidget);
    await tester.tap(find.text('Add Workspaces'));
    await tester.pumpAndSettle();
    expect(find.text('Add Workspaces To Stack'), findsOneWidget);

    final addField = tester.widget<AleraDropdownField<String?>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AleraDropdownField<String?> &&
            widget.labelText == 'Add Workspace',
      ),
    );
    addField.onChanged('workspace-three');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Workspaces'));
    await tester.pumpAndSettle();

    expect(request, isNotNull);
    expect(request!.layers, hasLength(1));
    expect(request!.layers.single.branch, 'feature/three');
  });

  testWidgets('disables base branch editing for a stack member', (
    tester,
  ) async {
    await tester.pumpWidget(_reviewView());

    await tester.tap(find.byTooltip('Edit Pull Request'));
    await tester.pumpAndSettle();

    final baseField = tester.widget<AleraDropdownField<String>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AleraDropdownField<String> &&
            widget.labelText == 'Base Branch',
      ),
    );
    expect(baseField.enabled, isFalse);
    expect(
      find.text('The base branch is managed by the pull request stack.'),
      findsOneWidget,
    );
  });

  testWidgets('collects pull requests in bottom-to-top order', (tester) async {
    List<int>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showDialog<List<int>>(
                  context: context,
                  builder: (_) =>
                      const PullRequestStackLinkDialog(currentReviewNumber: 42),
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '#41\n#42');
    await tester.tap(find.text('Create Stack'));
    await tester.pumpAndSettle();

    expect(result, <int>[41, 42]);
  });
}
