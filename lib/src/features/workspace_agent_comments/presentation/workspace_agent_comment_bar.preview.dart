import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera/src/features/workspace_agent_comments/presentation/workspace_agent_comment_bar.dart';
import 'package:flutter/material.dart';

@AleraPreview(
  name: 'Draft comments',
  group: 'Workspace agent comments',
  size: Size(480, 220),
)
Widget workspaceAgentCommentDraftBarPreview() {
  return SizedBox(
    width: 440,
    child: WorkspaceAgentCommentDraftBar(
      comments: const <WorkspaceAgentComment>[
        WorkspaceAgentComment(
          id: '1',
          kind: WorkspaceAgentCommentKind.file,
          path: 'lib/src/main.dart',
          body: 'Extract this helper.',
          lineRange: WorkspaceAgentCommentLineRange(startLine: 12, endLine: 18),
        ),
        WorkspaceAgentComment(
          id: '2',
          kind: WorkspaceAgentCommentKind.diff,
          path: 'lib/src/bar.dart',
          body: 'This looks wrong for empty input.',
          areaLabel: 'Unstaged',
          hunkHeader: '@@ -10,6 +12,8 @@ class Bar',
          lineRange: WorkspaceAgentCommentLineRange(startLine: 12, endLine: 14),
        ),
      ],
      onSend: () {},
      onClear: () {},
      onRemove: (_) {},
    ),
  );
}
