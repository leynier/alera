import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_field_decoration.dart';
import 'package:flutter/material.dart';

/// Composer anchored at the end of the pull-request conversation. It stays a
/// one-line prompt until activated so the panel does not carry an empty
/// multi-line field. Pure: [onSubmit] posts the body and reports whether the
/// forge accepted it; only then is the draft cleared.
class const PullRequestCommentComposer({
  super.key,
  required final String hintText,
  required final Future<bool> Function(String body) onSubmit,
  final bool busy = false,
  final bool posting = false,
}) extends StatefulWidget {
  @override
  State<PullRequestCommentComposer> createState() =>
      _PullRequestCommentComposerState();
}

class _PullRequestCommentComposerState
    extends State<PullRequestCommentComposer> {
  final TextEditingController _controller = TextEditingController();
  bool _expanded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    _controller.clear();
    setState(() => _expanded = false);
  }

  Future<void> _submit() async {
    final posted = await widget.onSubmit(_controller.text);
    if (posted && mounted) {
      _controller.clear();
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_expanded) {
      return Semantics(
        button: true,
        child: InkWell(
          onTap: widget.busy ? null : () => setState(() => _expanded = true),
          mouseCursor: SystemMouseCursors.text,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          child: Ink(
            padding: const EdgeInsets.all(AleraTokens.space12),
            decoration: BoxDecoration(
              color: AleraTokens.surface,
              border: Border.all(color: AleraTokens.borderSubtle),
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            ),
            child: Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.comment,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundFaint,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    widget.hintText,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        TextField(
          controller: _controller,
          autofocus: true,
          contextMenuBuilder: AleraTextActionsScope.buildContextMenu,
          enabled: !widget.busy,
          minLines: 3,
          maxLines: 8,
          keyboardType: .multiline,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foreground,
          ),
          cursorColor: AleraTokens.foreground,
          decoration: pullRequestFieldDecoration(theme, hint: widget.hintText),
        ),
        const SizedBox(height: AleraTokens.space8),
        Row(
          mainAxisAlignment: .end,
          children: <Widget>[
            TextButton(
              onPressed: widget.busy ? null : _cancel,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AleraTokens.space6),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) => FilledButton.icon(
                onPressed: widget.busy || value.text.trim().isEmpty
                    ? null
                    : _submit,
                icon: widget.posting
                    ? const SizedBox(
                        width: AleraTokens.iconMd,
                        height: AleraTokens.iconMd,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AleraIcons.send, size: AleraTokens.iconLg),
                label: const Text('Post Comment'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
