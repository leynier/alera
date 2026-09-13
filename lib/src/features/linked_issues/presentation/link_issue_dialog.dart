import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/linked_issues/application/linked_issue_repository.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue_link_result.dart';
import 'package:alera/src/features/linked_issues/presentation/issue_url_field.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter/material.dart';

/// Links (or replaces) the issue of one workspace. The dialog closes once the
/// URL is stored; a failed fetch surfaces as a toast rather than keeping the
/// user in the form, because the link itself already succeeded.
Future<void> showLinkIssueDialog(
  BuildContext context, {
  required LinkedIssueRepository repository,
  required String workspaceId,
  required String workspaceName,
  String? initialUrl,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _LinkIssueDialog(
      repository: repository,
      workspaceId: workspaceId,
      workspaceName: workspaceName,
      initialUrl: initialUrl,
    ),
  );
}

class const _LinkIssueDialog({
  required final LinkedIssueRepository repository,
  required final String workspaceId,
  required final String workspaceName,
  final String? initialUrl,
}) extends StatefulWidget {
  @override
  State<_LinkIssueDialog> createState() => _LinkIssueDialogState();
}

class _LinkIssueDialogState extends State<_LinkIssueDialog> {
  late final TextEditingController _url = TextEditingController(
    text: widget.initialUrl,
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Paste the URL of the issue to link.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.repository.link(widget.workspaceId, url);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      _announce(result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = userFacingExceptionMessage(error);
        });
      }
    }
  }

  void _announce(LinkedIssueLinkResult result) {
    final failure = result.fetchError;
    if (failure == null) {
      AleraToast.publish(message: 'Issue linked', tone: .success);
    } else if (failure.isUnsupported) {
      AleraToast.publish(
        message: 'Issue linked. No provider can read this tracker, so only the link is kept.',
      );
    } else {
      AleraToast.publish(
        message:
            'Issue linked, but its details could not be read: ${failure.message}',
        tone: .error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_saving,
      child: AleraDialog(
        maxWidth: AleraTokens.dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space20),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: <Widget>[
              Text('Link Issue', style: theme.textTheme.titleMedium),
              const SizedBox(height: AleraTokens.space6),
              Text(
                'Link an issue to ${widget.workspaceName}.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              const SizedBox(height: AleraTokens.space16),
              IssueUrlField(
                controller: _url,
                fetchIssue: widget.repository.fetch,
                enabled: !_saving,
                autofocus: true,
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: AleraTokens.space12),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.error,
                  ),
                ),
              ],
              const SizedBox(height: AleraTokens.space20),
              Row(
                mainAxisAlignment: .end,
                children: <Widget>[
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  FilledButton(
                    key: const ValueKey<String>('link-issue-submit'),
                    onPressed: _saving ? null : _save,
                    child: const Text('Link Issue'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
