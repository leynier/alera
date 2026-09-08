import 'package:alera/src/features/workbench/application/retired_workspace_invalidation.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment_prompt.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_agent_comment_controller.g.dart';

@Riverpod(keepAlive: true)
class WorkspaceAgentCommentController
    extends _$WorkspaceAgentCommentController {
  @override
  List<WorkspaceAgentComment> build(String workspaceId) {
    invalidateWhenWorkspaceRetired(ref, workspaceId);
    return const <WorkspaceAgentComment>[];
  }

  void add(WorkspaceAgentComment comment) {
    final body = comment.body.trim();
    if (body.isEmpty) {
      return;
    }
    final snippet = capWorkspaceAgentCommentSnippet(comment.snippet);
    state = List<WorkspaceAgentComment>.unmodifiableOf(<WorkspaceAgentComment>[
      ...state,
      WorkspaceAgentComment(
        id: comment.id,
        kind: comment.kind,
        path: comment.path,
        body: body,
        lineRange: comment.lineRange,
        hunkHeader: comment.hunkHeader,
        areaLabel: comment.areaLabel,
        snippet: snippet,
      ),
    ]);
  }

  void remove(String id) {
    final next = <WorkspaceAgentComment>[
      for (final comment in state)
        if (comment.id != id) comment,
    ];
    if (next.length == state.length) {
      return;
    }
    state = List<WorkspaceAgentComment>.unmodifiableOf(next);
  }

  void clear() {
    if (state.isEmpty) {
      return;
    }
    state = const <WorkspaceAgentComment>[];
  }
}
