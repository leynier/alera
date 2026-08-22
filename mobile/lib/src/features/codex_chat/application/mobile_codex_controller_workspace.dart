part of 'mobile_codex_controller.dart';

extension MobileCodexControllerWorkspace on MobileCodexController {
  bool get supportsImageUpload =>
      _client is MobileWorkspaceClient &&
      (_client! as MobileWorkspaceClient).supportsPromptImageUpload;

  bool get supportsWorkspaceFiles =>
      _client is MobileCodexWorkspaceClient &&
      (_client! as MobileCodexWorkspaceClient).supportsCodexWorkspaceFiles;

  bool get supportsFileUpload =>
      _client is MobileCodexWorkspaceClient &&
      (_client! as MobileCodexWorkspaceClient).supportsPromptFileUpload;

  Future<String> uploadImage({
    required String format,
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) async {
    final client = _client;
    if (client is! MobileWorkspaceClient) {
      throw UnsupportedError('Image uploads are unavailable on this client.');
    }
    try {
      final result = await (client as MobileWorkspaceClient).uploadPromptImage(
        format: format,
        sizeBytes: sizeBytes,
        openRead: openRead,
      );
      return result.hostPath;
    } catch (error, stackTrace) {
      _setError(error, stackTrace);
      rethrow;
    }
  }

  Future<PromptFileUploadResult> uploadFile({
    required String name,
    required int sizeBytes,
    required Stream<List<int>> Function() openRead,
  }) async {
    final client = _client;
    if (client is! MobileCodexWorkspaceClient) {
      throw UnsupportedError('File uploads are unavailable on this client.');
    }
    try {
      return await (client as MobileCodexWorkspaceClient).uploadPromptFile(
        name: name,
        sizeBytes: sizeBytes,
        openRead: openRead,
      );
    } catch (error, stackTrace) {
      _setError(error, stackTrace);
      rethrow;
    }
  }

  Future<MobileWorkspaceQuickOpenSession> startWorkspaceQuickOpen(
    String workspaceId, {
    String? cwd,
  }) {
    final client = _client;
    if (client is! MobileCodexWorkspaceClient) {
      throw UnsupportedError('Workspace files are unavailable on this client.');
    }
    return (client as MobileCodexWorkspaceClient).startWorkspaceQuickOpen(
      workspaceId,
      cwd: cwd,
    );
  }

  Future<List<MobileWorkspaceQuickOpenMatch>> searchWorkspaceQuickOpen(
    MobileWorkspaceQuickOpenSession session,
    String query,
  ) {
    final client = _client;
    if (client is! MobileCodexWorkspaceClient) {
      throw UnsupportedError('Workspace files are unavailable on this client.');
    }
    return (client as MobileCodexWorkspaceClient).searchWorkspaceQuickOpen(
      session,
      query,
    );
  }

  Future<void> stopWorkspaceQuickOpen(
    MobileWorkspaceQuickOpenSession session,
  ) async {
    final client = _client;
    if (client is MobileCodexWorkspaceClient) {
      await (client as MobileCodexWorkspaceClient).stopWorkspaceQuickOpen(
        session,
      );
    }
  }

  Future<List<MobileCodexSavedPrompt>> listSavedPrompts(
    String workspaceId, {
    String? cwd,
  }) {
    final client = _client;
    if (client is! MobileCodexWorkspaceClient) {
      return Future<List<MobileCodexSavedPrompt>>.value(
        const <MobileCodexSavedPrompt>[],
      );
    }
    return (client as MobileCodexWorkspaceClient).listCodexSavedPrompts(
      workspaceId,
      cwd: cwd,
    );
  }
}
