import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

/// Asks for a comment on [path] and pops with the trimmed text, or `null`
/// when cancelled.
Future<String?> showWorkspaceAgentCommentDialog(
  BuildContext context, {
  required String path,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => WorkspaceAgentCommentDialog(path: path),
  );
}

class const WorkspaceAgentCommentDialog({super.key, required final String path})
    extends StatefulWidget {
  @override
  State<WorkspaceAgentCommentDialog> createState() =>
      _WorkspaceAgentCommentDialogState();
}

class _WorkspaceAgentCommentDialogState
    extends State<WorkspaceAgentCommentDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final body = _controller.text.trim();
    if (body.isEmpty) {
      return;
    }
    Navigator.of(context).pop(body);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 480,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: <Widget>[
            Text('Comment on File', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space4),
            Text(
              widget.path,
              maxLines: 2,
              overflow: .ellipsis,
              style: AleraTokens.monoStyle.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _controller,
              autofocus: true,
              hintText: 'What should the agent do with this file?',
              keyboardType: TextInputType.multiline,
              minLines: 3,
              maxLines: 8,
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Add Comment'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
