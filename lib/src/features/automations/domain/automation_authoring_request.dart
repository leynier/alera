/// Where "New Automation" was started from. The composer seeds its
/// destination from this context and marks those fields From Context; the
/// user can change every one of them.
class const AutomationAuthoringRequest({
  final String? originWorkspaceId,
  final String? projectId,
  final String? sectionId,
  final String? editId,
  final String? cloneId,
});
