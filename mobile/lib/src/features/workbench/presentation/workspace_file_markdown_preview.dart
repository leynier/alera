import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/markdown/alera_markdown_view.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_markdown_image.dart';
import 'package:flutter/material.dart';

/// Rendered body of a workspace Markdown file. View-only: editing stays on
/// desktop.
class const WorkspaceFileMarkdownPreview({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final String relativePath,
  required final String markdown,
  required final ValueChanged<String> onLinkTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: AleraTokens.contentPadding,
      child: AleraMarkdownView(
        data: markdown,
        onLinkTap: onLinkTap,
        imageBuilder: (context, imageUrl, width, height) =>
            WorkspaceMarkdownImage(
              hostId: hostId,
              workspaceId: workspaceId,
              markdownPath: relativePath,
              imageUrl: imageUrl,
              width: width,
              height: height,
            ),
      ),
    );
  }
}
