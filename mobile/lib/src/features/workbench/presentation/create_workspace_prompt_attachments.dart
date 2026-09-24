part of 'create_workspace_screen.dart';

extension _CreateWorkspacePromptAttachments on _CreateWorkspaceScreenState {
  String? _workspaceFilesSourceId(String? projectId) {
    if (!widget.supportsWorkspaceFiles || projectId == null) return null;
    if (widget.supportsSharedCheckoutWorkspaces) return projectId;
    // Older runtimes only index an existing local task, not a project checkout.
    final candidates = widget.workspaces.where(
      (workspace) =>
          workspace.projectId == projectId &&
          !workspace.isRemote &&
          workspace.status == 'active',
    );
    for (final workspace in candidates) {
      if (workspace.id == _promptParentWorkspaceId) return workspace.id;
    }
    return candidates.where((workspace) => workspace.isMain).firstOrNull?.id;
  }

  Future<void> _showPromptAttachmentPicker(
    String? workspaceFilesSourceId,
  ) async {
    final source = await showPromptAttachmentSheet(
      context,
      allowPhotoLibrary:
          (_checkoutHostId == null || _checkoutHostId == 'local') &&
          widget.supportsPromptImageUpload,
      allowFiles:
          (_checkoutHostId == null || _checkoutHostId == 'local') &&
          widget.supportsPromptFileUpload,
      allowWorkspaceFile: workspaceFilesSourceId != null,
    );
    if (!mounted || source == null) {
      return;
    }
    switch (source) {
      case PromptAttachmentSource.photoLibrary:
        await _addPromptImages();
      case PromptAttachmentSource.files:
        await _addPromptFile();
      case PromptAttachmentSource.workspaceFile:
        await _addPromptWorkspaceFile(workspaceFilesSourceId!);
    }
  }

  Future<void> _addPromptFile() async {
    _update(() {
      _uploadingAttachment = true;
    });
    try {
      final file = await ref.read(promptFilePickerProvider).pickFile();
      if (file == null) {
        return;
      }
      final client = await ref.read(
        workspaceClientProvider(widget.hostId).future,
      );
      if (client is! MobileCodexWorkspaceClient) {
        throw UnsupportedError(
          'Update Alera on this host to add files to a prompt.',
        );
      }
      final fileClient = client as MobileCodexWorkspaceClient;
      if (!fileClient.supportsPromptFileUpload) {
        throw UnsupportedError(
          'Update Alera on this host to add files to a prompt.',
        );
      }
      final result = await fileClient.uploadPromptFile(
        name: file.name,
        sizeBytes: file.sizeBytes,
        openRead: file.openRead,
      );
      if (!mounted) {
        return;
      }
      ref
          .read(
            promptLocalAttachmentsProvider(
              widget.hostId,
              widget.initialLocalAttachmentPaths,
            ).notifier,
          )
          .add(result.hostPath);
      insertPromptPaths(_prompt, <String>[result.hostPath]);
      _update(() {
        _promptAttachmentError = null;
      });
    } on Object catch (error) {
      if (mounted) {
        _update(() {
          _promptAttachmentError = _promptAttachmentErrorMessage(error);
        });
      }
    } finally {
      if (mounted) {
        _update(() {
          _uploadingAttachment = false;
        });
      }
    }
  }

  Future<void> _addPromptWorkspaceFile(String sourceId) async {
    try {
      final client = await ref.read(
        workspaceClientProvider(widget.hostId).future,
      );
      if (client is! MobileCodexWorkspaceClient) {
        throw UnsupportedError(
          'Update Alera on this host to add workspace files to a prompt.',
        );
      }
      final filesClient = client as MobileCodexWorkspaceClient;
      if (!filesClient.supportsCodexWorkspaceFiles) {
        throw UnsupportedError(
          'Update Alera on this host to add workspace files to a prompt.',
        );
      }
      if (!mounted) {
        return;
      }
      final path = await showWorkspaceFilePickerSheet(
        context,
        start: () => widget.supportsSharedCheckoutWorkspaces
            ? requireSharedCheckoutClient(client).startProjectCheckoutQuickOpen(
                projectId: sourceId,
                checkoutHostId: _checkoutHostId,
              )
            : filesClient.startWorkspaceQuickOpen(sourceId),
        search: filesClient.searchWorkspaceQuickOpen,
        stop: filesClient.stopWorkspaceQuickOpen,
      );
      if (path == null || !mounted) {
        return;
      }
      insertPromptPaths(_prompt, <String>[path]);
      _update(() {
        _promptAttachmentError = null;
      });
    } on Object catch (error) {
      if (mounted) {
        _update(() {
          _promptAttachmentError = _promptAttachmentErrorMessage(error);
        });
      }
    }
  }

  Future<void> _addPromptImages() async {
    _update(() {
      _uploadingAttachment = true;
    });
    try {
      final images = await ref.read(promptImagePickerProvider).pickImages();
      if (images.isEmpty) {
        return;
      }
      final client = await ref.read(
        workspaceClientProvider(widget.hostId).future,
      );
      if (!client.supportsPromptImageUpload) {
        throw UnsupportedError(
          'Update Alera on this host to add images to a prompt.',
        );
      }
      for (final image in images) {
        final result = await client.uploadPromptImage(
          format: promptImageFormatForFileName(image.name),
          sizeBytes: image.sizeBytes,
          openRead: image.openRead,
        );
        if (!mounted) {
          return;
        }
        ref
            .read(
              promptLocalAttachmentsProvider(
                widget.hostId,
                widget.initialLocalAttachmentPaths,
              ).notifier,
            )
            .add(result.hostPath);
        insertPromptPaths(_prompt, <String>[result.hostPath]);
      }
      if (mounted) {
        _update(() {
          _promptAttachmentError = null;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        _update(() {
          _promptAttachmentError = _promptAttachmentErrorMessage(error);
        });
      }
    } finally {
      if (mounted) {
        _update(() {
          _uploadingAttachment = false;
        });
      }
    }
  }

  String _promptAttachmentErrorMessage(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isEmpty) {
      return 'Could not add the attachment. Try again.';
    }
    return 'Could not add the attachment: $message';
  }
}
