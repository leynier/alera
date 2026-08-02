import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/pull_requests/domain/hosted_review.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_field_decoration.dart';
import 'package:flutter/material.dart';

/// Link-mode field with an optional active pull-request suggestion.
class PullRequestLinkForm extends StatefulWidget {
  const PullRequestLinkForm({
    super.key,
    required this.controller,
    required this.busy,
    required this.suggestedReview,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool busy;
  final HostedReview? suggestedReview;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  State<PullRequestLinkForm> createState() => _PullRequestLinkFormState();
}

class _PullRequestLinkFormState extends State<PullRequestLinkForm> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestion = widget.suggestedReview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Pull Request',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space4),
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          contextMenuBuilder: AleraTextActionsScope.buildContextMenu,
          enabled: !widget.busy,
          autofocus: true,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foreground,
          ),
          cursorColor: AleraTokens.foreground,
          decoration: pullRequestFieldDecoration(
            theme,
            hint: '#123 or pull request URL',
          ),
          onChanged: (_) => widget.onChanged(),
          onSubmitted: (_) {
            if (!widget.busy) {
              widget.onSubmitted();
            }
          },
        ),
        if (suggestion != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          Text(
            'Suggested pull request',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
          Material(
            color: AleraTokens.surfaceVariant,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            child: InkWell(
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              onTap: widget.busy ? null : () => _select(suggestion),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AleraTokens.space12),
                decoration: BoxDecoration(
                  border: Border.all(color: AleraTokens.borderSubtle),
                  borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      AleraIcons.gitPullRequest,
                      size: AleraTokens.space16,
                      color: AleraTokens.foregroundMuted,
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: Text(
                        '#${suggestion.number} · ${suggestion.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _select(HostedReview suggestion) {
    widget.controller.text = '#${suggestion.number}';
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
    widget.onChanged();
    _focusNode.requestFocus();
  }
}
