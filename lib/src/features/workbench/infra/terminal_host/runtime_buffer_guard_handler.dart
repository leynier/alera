abstract interface class RuntimeBufferGuardHandler {
  List<Map<String, Object?>> lock({
    required String guardId,
    required Set<String> tabIds,
    required Set<String> workspacePaths,
  });

  void release(String guardId, {bool retired = false});
}
