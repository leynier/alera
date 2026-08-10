part of 'agent_runtime_overlay_service.dart';

extension _AgentRuntimeOverlayPrepare on AgentRuntimeOverlayService {
  Future<AgentRuntimeOverlayPreparation> _prepareOverlay({
    required String agentKey,
    required String terminalSessionId,
    required String publicEnvKey,
    required String overlayEnvKey,
    required String sourceEnvKey,
    required String defaultSourcePath,
    required String managedSubdirectory,
    required Map<String, String> managedFiles,
  }) async {
    final source = _resolveSource(
      publicEnvKey: publicEnvKey,
      overlayEnvKey: overlayEnvKey,
      sourceEnvKey: sourceEnvKey,
      defaultSourcePath: defaultSourcePath,
    );
    if (source.isExplicit && !_sourceExists(source.path)) {
      return AgentRuntimeOverlayPreparation(
        sourcePath: source.path,
        environment: <String, String>{publicEnvKey: source.path},
      );
    }

    final support = await _applicationSupportDirectory();
    final root = _overlayRoot(support, agentKey);
    final overlay = _overlayDirectory(root, terminalSessionId);
    try {
      _safeRemoveOverlay(overlay.path, root);
      overlay.createSync(recursive: true);
      if (_sourceExists(source.path)) {
        _mirrorSourceDirectory(
          sourcePath: source.path,
          overlayPath: overlay.path,
          managedSubdirectory: managedSubdirectory,
          managedFileNames: managedFiles.keys.toSet(),
        );
      }
      for (final entry in managedFiles.entries) {
        _writeManagedFile(
          p.join(overlay.path, managedSubdirectory, entry.key),
          entry.value,
        );
      }
    } catch (_) {
      _safeRemoveOverlay(overlay.path, root);
      if (source.isExplicit) {
        return AgentRuntimeOverlayPreparation(
          sourcePath: source.path,
          environment: <String, String>{publicEnvKey: source.path},
        );
      }
      return const AgentRuntimeOverlayPreparation(
        environment: <String, String>{},
      );
    }

    return AgentRuntimeOverlayPreparation(
      overlayPath: overlay.path,
      sourcePath: _sourceExists(source.path) ? source.path : null,
      environment: <String, String>{
        publicEnvKey: overlay.path,
        overlayEnvKey: overlay.path,
        if (_sourceExists(source.path)) sourceEnvKey: source.path,
      },
    );
  }
}
