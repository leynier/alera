part of 'terminal_tab_view.dart';

/// Attachment picking for the terminal composer. The upload path is the same
/// one the Codex composer and the create-workspace prompt use; only the
/// destination differs, because here the returned host path is inserted into
/// the compose field instead of a structured attachment list.
extension _TerminalAttachmentActions on _TerminalTabViewState {
  bool get _canAttach =>
      _attachmentImageClient != null ||
      _attachmentFileClient != null ||
      _attachmentWorkspaceClient != null;

  MobileWorkspaceClient? get _attachmentImageClient {
    final client = ref.read(workspaceClientProvider(widget.hostId)).value;
    return client != null && client.supportsPromptImageUpload ? client : null;
  }

  // Read as Object? because MobileCodexWorkspaceClient is a sibling interface
  // of MobileWorkspaceClient rather than a subtype: the runtime client
  // implements both, but neither declaration promotes from the other.
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

  Future<List<String>> _pickAttachments() async {
    final source = await showPromptAttachmentSheet(
      context,
      allowPhotoLibrary: _attachmentImageClient != null,
      allowFiles: _attachmentFileClient != null,
      allowWorkspaceFile: _attachmentWorkspaceClient != null,
    );
    if (!mounted || source == null) {
      return const <String>[];
    }
    return switch (source) {
      PromptAttachmentSource.photoLibrary => _attachImages(),
      PromptAttachmentSource.files => _attachFile(),
      PromptAttachmentSource.workspaceFile => _attachWorkspaceFile(),
    };
  }

  Future<List<String>> _attachImages() async {
    final client = _attachmentImageClient;
    if (client == null) {
      return const <String>[];
    }
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
        // promptImageFormatForFileName explains the accepted formats, and that
        // message is more useful than a generic failure.
        message: error is UnsupportedError
            ? (error.message ?? 'Image upload failed.')
            : 'Image upload failed.',
        error: error,
        stackTrace: stackTrace,
        retry: () => unawaited(_attachImages()),
      );
      return const <String>[];
    }
  }

  Future<List<String>> _attachFile() async {
    final client = _attachmentFileClient;
    if (client == null) {
      return const <String>[];
    }
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
        message: 'File upload failed.',
        error: error,
        stackTrace: stackTrace,
        retry: () => unawaited(_attachFile()),
      );
      return const <String>[];
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
    // A workspace path stays relative: the shell in that tab already runs from
    // the workspace root, so an absolute host path would only be longer.
    return path == null ? const <String>[] : <String>[path];
  }

  void _showAttachmentFailure({
    required String message,
    required Object error,
    required StackTrace stackTrace,
    required VoidCallback retry,
  }) {
    Logger('TerminalTabView').warning(message, error, stackTrace);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Retry', onPressed: retry),
      ),
    );
  }
}
