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
        composing: TextRange.empty,
      );
    });
  }

  Future<void> _pickImage(MobileCodexController controller) async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;
      final path = await controller.uploadImage(
        format: promptImageFormatForFileName(image.name),
        sizeBytes: await image.length(),
        openRead: () => image.openRead(),
      );
      if (!mounted) return;
      _setDraftState(() {
        _attachments.add(<String, Object?>{
          'type': 'localImage',
          'origin': 'attachment',
          'name': image.name,
          'path': path,
        });
      });
    } on Object catch (error, stackTrace) {
      _showAttachmentUploadFailure(
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
          mainAxisSize: MainAxisSize.min,
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
    try {
      final file = await openFile();
      if (file == null || !mounted) return;
      final upload = await controller.uploadFile(
        name: file.name,
        sizeBytes: await file.length(),
        openRead: file.openRead,
      );
      if (!mounted) return;
      _setDraftState(() {
        _attachments.add(<String, Object?>{
          'type': mobileCodexIsAudioFile(file.name, file.mimeType)
              ? 'localAudio'
              : 'file',
          'origin': 'attachment',
          'name': file.name,
          'path': upload.hostPath,
        });
      });
    } on Object catch (error, stackTrace) {
      _showAttachmentUploadFailure(
        message: 'File upload failed.',
        error: error,
        stackTrace: stackTrace,
        retry: () => unawaited(_pickFile(controller)),
      );
    }
  }

  void _showAttachmentUploadFailure({
    required String message,
    required Object error,
    required StackTrace stackTrace,
    required VoidCallback retry,
  }) {
    _MobileCodexChatScreenState._logger.warning(message, error, stackTrace);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
    final path = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.78,
        child: _MobileWorkspaceFilePicker(
          controller: controller,
          workspaceId: widget.workspaceId,
          cwd: cwd,
        ),
      ),
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
