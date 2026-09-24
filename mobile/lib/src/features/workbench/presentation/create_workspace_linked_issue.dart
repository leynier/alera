part of 'create_workspace_screen.dart';

/// The optional issue field of both New Workspace modes. A resolved issue
/// fills the branch, the name or the prompt only while they are empty or still
/// hold what an earlier issue filled in, so typed input always stays.
extension _CreateWorkspaceLinkedIssue on _CreateWorkspaceScreenState {
  List<Widget> _linkedIssueField({
    required bool forPrompt,
    required bool enabled,
  }) {
    if (!widget.supportsLinkedIssues) {
      return const <Widget>[];
    }
    final issues = ref.read(
      linkedIssuesControllerProvider(widget.hostId).notifier,
    );
    return <Widget>[
      MobileIssueUrlField(
        controller: _issueUrl,
        fetchIssue: issues.fetch,
        enabled: enabled,
        onResolved: forPrompt ? _applyIssueToPrompt : _applyIssueToManualForm,
      ),
      const SizedBox(height: AleraTokens.spaceLg),
    ];
  }

  String? _linkedIssueUrl() {
    final url = _issueUrl.text.trim();
    return !widget.supportsLinkedIssues || url.isEmpty ? null : url;
  }

  void _applyIssueToManualForm(MobileIssueDetails issue) {
    _update(() {
      final branch = _branch.text.trim();
      if (!_reuseExistingBranch &&
          (branch.isEmpty || branch == _branchFromIssue)) {
        _branchFromIssue = mobileIssueBranchName(issue);
        _branch.text = _branchFromIssue!;
      }
      final name = _name.text.trim();
      if (name.isEmpty || name == _nameFromIssue) {
        _nameFromIssue = mobileIssueWorkspaceName(issue);
        _name.text = _nameFromIssue!;
      }
    });
  }

  void _applyIssueToPrompt(MobileIssueDetails issue) {
    final prompt = _prompt.text.trim();
    if (prompt.isNotEmpty && prompt != _promptFromIssue) {
      return;
    }
    _update(() {
      _promptFromIssue = mobileIssuePrompt(issue);
      _prompt.text = _promptFromIssue!;
    });
  }
}
