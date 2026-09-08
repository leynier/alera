import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/features/workspace_agent_comments/presentation/workspace_agent_comment_dialog.dart';
import 'package:flutter/material.dart';

@AleraPreview(
  name: 'File comment',
  group: 'Workspace agent comments',
  size: Size(460, 360),
)
WidgetBuilder workspaceAgentCommentDialogPreview() =>
    (context) => const WorkspaceAgentCommentDialog(
      title: 'Comment on File',
      path: 'lib/src/main.dart',
      locationLabel: 'lib/src/main.dart · lines 12-18',
      snippet: 'void start() {\n  run();\n}',
    );
