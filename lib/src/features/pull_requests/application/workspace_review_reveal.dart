import 'package:alera/src/features/workbench/application/retired_workspace_invalidation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'workspace_review_reveal.g.dart';

@Riverpod(keepAlive: true)
class WorkspaceReviewReveal extends _$WorkspaceReviewReveal {
  @override
  int? build(String workspaceId) {
    invalidateWhenWorkspaceRetired(ref, workspaceId);
    return null;
  }

  void reveal(int number) => state = number;
}
