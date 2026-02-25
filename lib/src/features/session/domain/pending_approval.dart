enum PermissionMode { defaultMode, fullAccess }

class PendingApproval {
  const PendingApproval({
    required this.requestId,
    required this.method,
    required this.description,
  });

  final Object requestId;
  // 'item/commandExecution/requestApproval' or 'item/fileChange/requestApproval'
  final String method;
  // Human-readable summary of what is being approved.
  final String description;
}
