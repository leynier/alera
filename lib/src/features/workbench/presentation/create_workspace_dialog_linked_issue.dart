part of 'create_workspace_dialog.dart';

/// The optional issue field of the manual form, and the prefill it drives.
///
/// A resolved issue fills the branch and the name only while they are still
/// empty or still hold what an earlier issue filled in, so pasting a different
/// URL updates them but anything the user typed stays.
extension _CreateWorkspaceDialogLinkedIssue on _CreateWorkspaceDialogState {
  Widget? _linkedIssueField() {
    final fetchIssue = widget.fetchIssue;
    if (fetchIssue == null) {
      return null;
    }
    return IssueUrlField(
      controller: _issueUrlController,
      fetchIssue: fetchIssue,
      enabled: !_creating,
      onResolved: _applyResolvedIssue,
    );
  }

  String? _linkedIssueUrl() {
    final url = _issueUrlController.text.trim();
    return widget.fetchIssue == null || url.isEmpty ? null : url;
  }

  void _applyResolvedIssue(IssueDetails issue) {
    final branch = issueBranchName(issue);
    final currentBranch = _newBranchController.text.trim();
    final fillBranch =
        !_reuseExistingBranch &&
        (currentBranch.isEmpty || currentBranch == _branchFromIssue);
    _update(() {
      if (!_nameTouched || _nameFromIssue) {
        _nameController.text = issueWorkspaceName(issue);
        _nameTouched = true;
        _nameFromIssue = true;
      }
      if (fillBranch) {
        _newBranchController.text = branch;
        _branchFromIssue = branch;
      }
    });
    if (fillBranch) {
      _onNewBranchChanged(branch);
    }
  }
}
