import 'package:alera_mobile/src/features/linked_issues/application/linked_issues_controller.dart';
import 'package:alera_mobile/src/features/linked_issues/domain/mobile_linked_issue.dart';
import 'package:alera_mobile/src/features/linked_issues/presentation/mobile_issue_url_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Links (or replaces) a workspace's issue. Returns the result, or null when
/// the user cancelled.
Future<MobileLinkIssueResult?> showMobileLinkIssueDialog(
  BuildContext context, {
  required String hostId,
  required String workspaceId,
  String? initialUrl,
}) {
  return showDialog<MobileLinkIssueResult>(
    context: context,
    builder: (_) => _MobileLinkIssueDialog(
      hostId: hostId,
      workspaceId: workspaceId,
      initialUrl: initialUrl,
    ),
  );
}

class const _MobileLinkIssueDialog({
  required final String hostId,
  required final String workspaceId,
  final String? initialUrl,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_MobileLinkIssueDialog> createState() =>
      _MobileLinkIssueDialogState();
}

class _MobileLinkIssueDialogState
    extends ConsumerState<_MobileLinkIssueDialog> {
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
      final result = await ref
          .read(linkedIssuesControllerProvider(widget.hostId).notifier)
          .link(widget.workspaceId, url);
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(
      linkedIssuesControllerProvider(widget.hostId).notifier,
    );
    return AlertDialog(
      title: const Text('Link Issue'),
      content: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          MobileIssueUrlField(
            controller: _url,
            fetchIssue: controller.fetch,
            enabled: !_saving,
            autofocus: true,
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Link Issue'),
        ),
      ],
    );
  }
}

/// Snackbar copy for a finished link: the fetch outcome, never an error for
/// the link itself, which already succeeded.
String mobileLinkIssueMessage(MobileLinkIssueResult result) {
  return switch (result.fetchErrorCode) {
    null => 'Issue linked',
    'unsupported' => 'Issue linked. No provider can read this tracker, so only the link is kept.',
    _ =>
      'Issue linked, but its details could not be read: ${result.fetchErrorMessage}',
  };
}
