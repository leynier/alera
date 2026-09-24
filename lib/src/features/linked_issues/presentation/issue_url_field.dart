import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/linked_issues/domain/issue_details.dart';
import 'package:alera/src/features/linked_issues/presentation/linked_issue_state_icon.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter/material.dart';

/// Pause after the last keystroke before the issue is fetched, so pasting or
/// typing a URL costs one forge CLI call rather than one per character.
const Duration issueUrlResolveDelay = Duration(milliseconds: 400);

/// Optional issue URL input that resolves the issue in the background and
/// shows its number, state and title inline. A failed resolve is a warning,
/// never a blocker: the URL is still linked.
class const IssueUrlField({
  super.key,
  required final TextEditingController controller,
  required final Future<IssueDetails> Function(String url) fetchIssue,
  final ValueChanged<IssueDetails>? onResolved,
  final bool enabled = true,
  final bool autofocus = false,
  final String labelText = 'Issue URL',
}) extends StatefulWidget {
  @override
  State<IssueUrlField> createState() => _IssueUrlFieldState();
}

class _IssueUrlFieldState extends State<IssueUrlField> {
  Timer? _debounce;
  String _requestedUrl = '';
  bool _resolving = false;
  IssueDetails? _issue;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    if (widget.controller.text.trim().isNotEmpty) {
      _schedule();
    }
  }

  @override
  void didUpdateWidget(IssueUrlField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (widget.controller.text.trim() == _requestedUrl) {
      return;
    }
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    final url = widget.controller.text.trim();
    _requestedUrl = url;
    setState(() {
      _issue = null;
      _error = null;
      _resolving = url.isNotEmpty;
    });
    if (url.isEmpty) {
      return;
    }
    _debounce = Timer(issueUrlResolveDelay, () => unawaited(_resolve(url)));
  }

  Future<void> _resolve(String url) async {
    try {
      final issue = await widget.fetchIssue(url);
      if (!mounted || url != _requestedUrl) {
        return;
      }
      setState(() {
        _issue = issue;
        _resolving = false;
      });
      widget.onResolved?.call(issue);
    } catch (error) {
      if (!mounted || url != _requestedUrl) {
        return;
      }
      setState(() {
        _error = userFacingExceptionMessage(error);
        _resolving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issue = _issue;
    final error = _error;
    final caption = theme.textTheme.bodySmall;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraTextField(
          key: const ValueKey<String>('issue-url-field'),
          controller: widget.controller,
          labelText: widget.labelText,
          hintText: 'Paste a GitHub, GitLab, Azure DevOps, or tracker URL',
          keyboardType: TextInputType.url,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
        ),
        if (_resolving || issue != null || error != null)
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space6),
            child: Row(
              children: <Widget>[
                if (_resolving)
                  const SizedBox.square(
                    dimension: AleraTokens.iconSm,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else if (issue != null)
                  LinkedIssueStateIcon(state: issue.state)
                else
                  const Icon(
                    AleraIcons.error,
                    size: AleraTokens.iconSm,
                    color: AleraTokens.warning,
                  ),
                const SizedBox(width: AleraTokens.space6),
                Expanded(
                  child: Text(
                    _resolving
                        ? 'Resolving issue'
                        : issue != null
                        ? '#${issue.number} · ${issue.displayState} · ${issue.title}'
                        : 'Could not read the issue: $error The link will still be saved.',
                    key: const ValueKey<String>('issue-url-field-status'),
                    maxLines: 2,
                    overflow: .ellipsis,
                    style: caption?.copyWith(
                      color: issue != null || _resolving
                          ? AleraTokens.foregroundMuted
                          : AleraTokens.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
