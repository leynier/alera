import 'package:alera/src/features/pull_requests/application/workspace_review_reveal.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void revealWorkspaceReview(WidgetRef ref, String workspaceId, int number) {
  if (ref.read(workbenchControllerProvider).activeWorkspaceId != workspaceId) {
    return;
  }
  ref.read(workspaceReviewRevealProvider(workspaceId).notifier).reveal(number);
  ref
      .read(workbenchControllerProvider.notifier)
      .setContextPanelTab(.pullRequests);
}
