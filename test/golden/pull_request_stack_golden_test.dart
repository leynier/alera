import 'package:alchemist/alchemist.dart';
import 'package:alera/src/features/pull_requests/domain/review_stack_workspace_models.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_stack_workspace_dialog.dart';
import 'package:flutter/material.dart';

import 'alera_golden_harness.dart';

void main() {
  runAleraGoldenTests(() {
    goldenTest(
      'renders workspace stack creation',
      fileName: 'pull_request_stack_workspace_dialog',
      constraints: const BoxConstraints.tightFor(width: 840, height: 900),
      builder: () => GoldenTestScenario(
        name: 'Create Stack From Workspaces',
        child: const SizedBox(
          width: 780,
          height: 760,
          child: PullRequestStackWorkspaceDialog(
            currentTitle: 'feat: add stacked pull requests',
            currentBody: 'Create and manage a native GitHub stack from Alera.',
            currentDraft: false,
            candidates: <ReviewStackWorkspaceCandidate>[
              ReviewStackWorkspaceCandidate(
                workspaceId: 'workspace-foundation',
                name: 'Foundation',
                repoPath: '/workspaces/foundation',
                branch: 'feature/stack-foundation',
                current: false,
              ),
              ReviewStackWorkspaceCandidate(
                workspaceId: 'workspace-ui',
                name: 'Stack UI',
                repoPath: '/workspaces/stack-ui',
                branch: 'feature/stack-ui',
                current: true,
                sourceBranch: 'feature/stack-foundation',
                parentWorkspaceId: 'workspace-foundation',
              ),
            ],
            baseBranches: <String>['main', 'develop'],
            suggestedBaseBranch: 'main',
            defaultDraft: false,
          ),
        ),
      ),
    );
  });
}
