typedef WorkspaceParentSelectionKey = ({
  bool isDefault,
  String projectId,
  String projectName,
  String workspaceId,
  String workspaceName,
});

int compareWorkspaceParentSelectionKeys(
  WorkspaceParentSelectionKey left,
  WorkspaceParentSelectionKey right, {
  String? preferredProjectId,
}) {
  final leftPreferred = left.projectId == preferredProjectId;
  final rightPreferred = right.projectId == preferredProjectId;
  if (leftPreferred != rightPreferred) {
    return leftPreferred ? -1 : 1;
  }

  final normalizedProjectOrder = left.projectName.toLowerCase().compareTo(
    right.projectName.toLowerCase(),
  );
  if (normalizedProjectOrder != 0) {
    return normalizedProjectOrder;
  }
  final projectNameOrder = left.projectName.compareTo(right.projectName);
  if (projectNameOrder != 0) {
    return projectNameOrder;
  }
  final projectIdOrder = left.projectId.compareTo(right.projectId);
  if (projectIdOrder != 0) {
    return projectIdOrder;
  }

  if (left.isDefault != right.isDefault) {
    return left.isDefault ? -1 : 1;
  }
  final normalizedWorkspaceOrder = left.workspaceName.toLowerCase().compareTo(
    right.workspaceName.toLowerCase(),
  );
  if (normalizedWorkspaceOrder != 0) {
    return normalizedWorkspaceOrder;
  }
  final workspaceNameOrder = left.workspaceName.compareTo(right.workspaceName);
  if (workspaceNameOrder != 0) {
    return workspaceNameOrder;
  }
  return left.workspaceId.compareTo(right.workspaceId);
}
