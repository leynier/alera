import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:flutter/material.dart';

Future<String?> showWorkspaceAgentCommentDialog(
  BuildContext context, {
  required String title,
  required String path,
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

class WorkspaceAgentCommentDialog extends StatefulWidget {
  const WorkspaceAgentCommentDialog({
    super.key,
    required this.title,
    required this.path,
    this.locationLabel,
    this.snippet,
  });

  final String title;
  final String path;
  final String? locationLabel;
  final String? snippet;

  @override
  State<WorkspaceAgentCommentDialog> createState() =>
      _WorkspaceAgentCommentDialogState();
}

class _WorkspaceAgentCommentDialogState
    extends State<WorkspaceAgentCommentDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
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
      maxWidth: AleraTokens.dialogWidth,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space16,
          AleraTokens.space12,
          AleraTokens.space16,
          AleraTokens.space16,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: widget.title,
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space8),
            Text(
              location == null || location.isEmpty ? widget.path : location,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
                fontFamily: 'JetBrains Mono',
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
                      fontSize: 12,
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              keyboardType: .multiline,
              hintText: 'What should the agent do?',
            ),
            const SizedBox(height: AleraTokens.space16),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Cancel',
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: const Text(
                      'Add Comment',
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
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
