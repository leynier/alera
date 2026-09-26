/// The terminal tabs a workspace sleep stopped, as the runtime host records
/// them. Their records stay for resume, so clients need this to show them as
/// closed until the workspace wakes.
abstract interface class WorkspaceSleepRepository {
  /// Slept terminal tab ids by workspace. Empty on a host without
  /// `workspaceSleepStateV1`.
  Stream<Map<String, List<String>>> watchSleptWorkspaceTabs();
}
