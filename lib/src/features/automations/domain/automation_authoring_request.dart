/// Where "New Automation" was started from. The origin is only context: it
/// never selects an execution target type.
class const AutomationAuthoringRequest({
  final String? originWorkspaceId,
  final String? projectId,
  final String? editId,
  final String? cloneId,
  final Map<String, Object?>? template,
});
