part of 'prompt_workspace_dialog.dart';

/// The optional issue field of the From Prompt form. A resolved issue fills
/// the prompt only while it is empty or still holds an earlier issue's text.
extension _PromptWorkspaceDialogLinkedIssue on _PromptWorkspaceDialogState {
  List<Widget> _linkedIssueField() {
    final fetchIssue = widget.fetchIssue;
    if (fetchIssue == null) {
      return const <Widget>[];
    }
    return <Widget>[
      IssueUrlField(
        controller: _issueUrlController,
        fetchIssue: fetchIssue,
        enabled: !_working && _created == null,
        onResolved: _applyResolvedIssue,
      ),
      const SizedBox(height: AleraTokens.space12),
    ];
  }

  String? _linkedIssueUrl() {
    final url = _issueUrlController.text.trim();
    return widget.fetchIssue == null || url.isEmpty ? null : url;
  }

  void _applyResolvedIssue(IssueDetails issue) {
    final current = _promptController.text.trim();
    if (current.isNotEmpty && current != _promptFromIssue) {
      return;
    }
    final prompt = issuePrompt(issue);
    _update(() {
      _promptController.text = prompt;
      _promptFromIssue = prompt;
    });
  }
}
