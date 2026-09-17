part of 'agent_profile_launch_sheet.dart';

extension on _AgentProfileLaunchSheetState {
  bool get _canAttach =>
      _attachmentImageClient != null ||
      _attachmentFileClient != null ||
      _attachmentWorkspaceClient != null;

  MobileWorkspaceClient? get _attachmentImageClient {
    final client = ref.read(workspaceClientProvider(widget.hostId)).value;
    return client != null && client.supportsPromptImageUpload ? client : null;
  }

  Object? get _rawWorkspaceClient =>
      ref.read(workspaceClientProvider(widget.hostId)).value;

  MobileCodexWorkspaceClient? get _attachmentFileClient {
    final Object? client = _rawWorkspaceClient;
    if (client is MobileCodexWorkspaceClient &&
        client.supportsPromptFileUpload) {
      return client;
    }
    return null;
  }

  MobileCodexWorkspaceClient? get _attachmentWorkspaceClient {
    final Object? client = _rawWorkspaceClient;
    if (client is MobileCodexWorkspaceClient &&
        client.supportsCodexWorkspaceFiles) {
      return client;
    }
    return null;
  }

  Future<void> _showAttachmentPicker() async {
    if (_busy) {
      return;
    }
    final source = await showPromptAttachmentSheet(
      context,
      allowPhotoLibrary: _attachmentImageClient != null,
      allowFiles: _attachmentFileClient != null,
      allowWorkspaceFile: _attachmentWorkspaceClient != null,
    );
    if (!mounted || source == null) {
      return;
    }
    final paths = await switch (source) {
      PromptAttachmentSource.photoLibrary => _attachImages(),
      PromptAttachmentSource.files => _attachFile(),
      PromptAttachmentSource.workspaceFile => _attachWorkspaceFile(),
    };
    if (!mounted || paths.isEmpty) {
      return;
    }
    insertPromptPaths(_promptController, paths);
    _update(() => _error = null);
  }

  Future<List<String>> _attachImages() async {
    final client = _attachmentImageClient;
    if (client == null) {
      return const <String>[];
    }
    _update(() => _attaching = true);
    try {
      final images = await ref.read(promptImagePickerProvider).pickImages();
      final paths = <String>[];
      for (final image in images) {
        final result = await client.uploadPromptImage(
          format: promptImageFormatForFileName(image.name),
          sizeBytes: image.sizeBytes,
          openRead: image.openRead,
        );
        paths.add(result.hostPath);
      }
      return paths;
    } on Object catch (error, stackTrace) {
      _showAttachmentFailure(
        message: error is UnsupportedError
            ? (error.message ?? 'Image upload failed.')
            : 'Could not add the attachment. Try again.',
        error: error,
        stackTrace: stackTrace,
      );
      return const <String>[];
    } finally {
      if (mounted) {
        _update(() => _attaching = false);
      }
    }
  }

  Future<List<String>> _attachFile() async {
    final client = _attachmentFileClient;
    if (client == null) {
      return const <String>[];
    }
    _update(() => _attaching = true);
    try {
      final file = await ref.read(promptFilePickerProvider).pickFile();
      if (file == null) {
        return const <String>[];
      }
      final upload = await client.uploadPromptFile(
        name: file.name,
        sizeBytes: file.sizeBytes,
        openRead: file.openRead,
      );
      return <String>[upload.hostPath];
    } on Object catch (error, stackTrace) {
      _showAttachmentFailure(
        message: 'Could not add the attachment. Try again.',
        error: error,
        stackTrace: stackTrace,
      );
      return const <String>[];
    } finally {
      if (mounted) {
        _update(() => _attaching = false);
      }
    }
  }

  Future<List<String>> _attachWorkspaceFile() async {
    final client = _attachmentWorkspaceClient;
    if (client == null) {
      return const <String>[];
    }
    final path = await showWorkspaceFilePickerSheet(
      context,
      start: () => client.startWorkspaceQuickOpen(widget.workspaceId),
      search: client.searchWorkspaceQuickOpen,
      stop: client.stopWorkspaceQuickOpen,
    );
    return path == null ? const <String>[] : <String>[path];
  }

  void _showAttachmentFailure({
    required String message,
    required Object error,
    required StackTrace stackTrace,
  }) {
    _agentProfileLaunchLogger.warning(message, error, stackTrace);
    if (mounted) {
      _update(() => _error = message);
    }
  }
}
