import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

/// Asks for a comment on [path] and pops with the trimmed text, or `null`
/// when cancelled.
Future<String?> showWorkspaceAgentCommentDialog(
  BuildContext context, {
  required String path,
  String title = 'Comment on File',
  String? locationLabel,
  String? snippet,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => WorkspaceAgentCommentDialog(
      title: title,
      path: path,
      locationLabel: locationLabel,
      snippet: snippet,
    ),
  );
}

class const WorkspaceAgentCommentDialog({
  super.key,
  required final String path,
  final String title = 'Comment on File',
  final String? locationLabel,
  final String? snippet,
}) extends StatefulWidget {
  @override
  State<WorkspaceAgentCommentDialog> createState() =>
      _WorkspaceAgentCommentDialogState();
}

class _WorkspaceAgentCommentDialogState
    extends State<WorkspaceAgentCommentDialog> {
  final TextEditingController _controller = TextEditingController();

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

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
    final location = widget.locationLabel?.trim();
    final snippet = widget.snippet?.trim();
    return AleraDialog(
      maxWidth: 480,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: <Widget>[
            Text(widget.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space4),
            Text(
              location == null || location.isEmpty ? widget.path : location,
              maxLines: 2,
              overflow: .ellipsis,
              style: AleraTokens.monoStyle.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            if (snippet != null && snippet.isNotEmpty) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AleraTokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                  border: Border.all(color: AleraTokens.borderSubtle),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AleraTokens.space8),
                  child: Text(
                    snippet,
                    maxLines: 6,
                    overflow: .ellipsis,
                    style: AleraTokens.monoStyle.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _controller,
              autofocus: true,
              hintText: 'What should the agent do?',
              keyboardType: .multiline,
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
                    onPressed: _canSubmit ? _submit : null,
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
