abstract interface class RuntimeBufferGuardHandler {
  List<Map<String, Object?>> lock({
    required String guardId,
    required Set<String> tabIds,
    required Set<String> workspacePaths,
  });

  void release(String guardId, {bool retired = false});
}

/// A buffer guard handler that can also settle dirty editors before it locks
/// them, so a workspace operation started outside this app (the CLI or an MCP
/// client) can save or discard them the way the app's own dialogs do. The
/// client announces `checkoutBufferSaveV1` in `hello` only for these.
abstract interface class RuntimeBufferGuardResolver
    implements RuntimeBufferGuardHandler {
  /// Saves the dirty editors in scope, or discards them when [discard] is
  /// true, then locks the scope like [lock]. Returns the blockers: editors
  /// that could not be saved or are still busy.
  Future<List<Map<String, Object?>>> resolveAndLock({
    required String guardId,
    required Set<String> tabIds,
    required Set<String> workspacePaths,
    required bool discard,
  });
}
