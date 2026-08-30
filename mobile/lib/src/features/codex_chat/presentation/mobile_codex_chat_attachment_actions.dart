part of 'mobile_codex_chat_screen.dart';

// This part keeps attachment actions separate from session and timeline actions.
// ignore_for_file: invalid_use_of_protected_member

extension _MobileCodexAttachmentActions on _MobileCodexChatScreenState {
  void _removeAttachment(Map<String, Object?> attachment) {
    _setDraftState(() {
      _attachments.remove(attachment);
      if (attachment['origin'] != 'mention') return;
      final path = attachment['path']?.toString() ?? '';
      final range = mobileCodexFileReferenceRange(_composer.text, path);
      if (range == null) return;
      var start = range.start;
      var end = range.end;
      if (end < _composer.text.length && _composer.text[end] == ' ') {
        end += 1;
      } else if (start > 0 && _composer.text[start - 1] == ' ') {
        start -= 1;
      }
      final value = _composer.value;
      final nextText = value.text.replaceRange(start, end, '');
      int adjustedOffset(int offset) {
        if (offset <= start) return offset;
        if (offset <= end) return start;
        return offset - (end - start);
      }

      _composer.value = value.copyWith(
        text: nextText,
        selection: TextSelection(
          baseOffset: adjustedOffset(value.selection.baseOffset),
          extentOffset: adjustedOffset(value.selection.extentOffset),
        ),
        composing: .empty,
      );
    });
  }

  /// Adds an attachment whose upload may have outlived this state. The draft
  /// store is keyed by host and tab and outlives the screen, so a pick that
  /// completes after the tab body was rebuilt still reaches the composer.
  void _addUploadedAttachment(Map<String, Object?> attachment) {
    if (mounted) {
      _setDraftState(() => _attachments.add(attachment));
      return;
    }
    _draftStore.addAttachment(widget.hostId, widget.tabId, attachment);
  }

  Future<void> _pickImage(MobileCodexController controller) async {
    final messenger = mounted ? ScaffoldMessenger.maybeOf(context) : null;
    try {
      final image = await ImagePicker().pickImage(source: .gallery);
      if (image == null) return;
      final path = await controller.uploadImage(
        format: promptImageFormatForFileName(image.name),
        sizeBytes: await image.length(),
        openRead: () => image.openRead(),
      );
      _addUploadedAttachment(<String, Object?>{
        'type': 'localImage',
        'origin': 'attachment',
        'name': image.name,
        'path': path,
      });
    } on Object catch (error, stackTrace) {
      _showAttachmentUploadFailure(
        messenger: messenger,
        message: 'Image upload failed.',
        error: error,
        stackTrace: stackTrace,
        retry: () => unawaited(_pickImage(controller)),
      );
    }
  }

  Future<void> _showAttachmentPicker(
    MobileCodexController controller, {
    String? cwd,
  }) async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            if (controller.supportsImageUpload)
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Photo Library'),
                onTap: () => Navigator.of(context).pop('image'),
              ),
            if (controller.supportsFileUpload)
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('Files'),
                onTap: () => Navigator.of(context).pop('file'),
              ),
            if (controller.supportsWorkspaceFiles)
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Workspace File'),
                onTap: () => Navigator.of(context).pop('workspace'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (selection) {
      case 'image':
        await _pickImage(controller);
      case 'file':
        await _pickFile(controller);
      case 'workspace':
        await _pickWorkspaceFile(controller, cwd: cwd);
      case null:
        return;
    }
  }

  Future<void> _pickFile(MobileCodexController controller) async {
    final messenger = mounted ? ScaffoldMessenger.maybeOf(context) : null;
    try {
      final file = await openFile();
      if (file == null) return;
      final upload = await controller.uploadFile(
        name: file.name,
        sizeBytes: await file.length(),
        openRead: file.openRead,
      );
      _addUploadedAttachment(<String, Object?>{
        'type': mobileCodexIsAudioFile(file.name, file.mimeType)
            ? 'localAudio'
            : 'file',
        'origin': 'attachment',
        'name': file.name,
        'path': upload.hostPath,
      });
    } on Object catch (error, stackTrace) {
      _showAttachmentUploadFailure(
        messenger: messenger,
        message: 'File upload failed.',
        error: error,
        stackTrace: stackTrace,
        retry: () => unawaited(_pickFile(controller)),
      );
    }
  }

  /// The messenger is captured before the picker runs. Reporting through
  /// `context` instead loses the failure exactly when it matters, because the
  /// state that started the pick may be gone by the time the upload fails.
  void _showAttachmentUploadFailure({
    required ScaffoldMessengerState? messenger,
    required String message,
    required Object error,
    required StackTrace stackTrace,
    required VoidCallback retry,
  }) {
    _MobileCodexChatScreenState._logger.warning(message, error, stackTrace);
    if (messenger == null || !messenger.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Retry', onPressed: retry),
      ),
    );
  }

  Future<void> _pickWorkspaceFile(
    MobileCodexController controller, {
    String? cwd,
  }) async {
    final path = await showWorkspaceFilePickerSheet(
      context,
      start: () =>
          controller.startWorkspaceQuickOpen(widget.workspaceId, cwd: cwd),
      search: controller.searchWorkspaceQuickOpen,
      stop: controller.stopWorkspaceQuickOpen,
    );
    if (path == null || !mounted) return;
    _setDraftState(() {
      _attachments.add(<String, Object?>{
        'type': 'mention',
        'origin': 'mention',
        'name': _mobileBaseName(path),
        'path': path,
        if (cwd?.trim().isNotEmpty == true) 'cwd': cwd!.trim(),
      });
    });
  }
}
