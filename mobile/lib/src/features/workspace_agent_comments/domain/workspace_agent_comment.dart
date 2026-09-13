/// A local draft comment on a workspace file, destined for an agent.
///
/// Mirrors the desktop `WorkspaceAgentComment` for file comments only; diff
/// comments stay on desktop.
class const WorkspaceAgentComment({
  required final String id,
  required final String path,
  required final String body,
  final String? snippet,
});
