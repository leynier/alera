part of 'codex_chat_surface.dart';

extension _CodexDraftActions on _CodexChatSurfaceState {
  String get _activeCodexWorkspacePath {
    final cwd = ref
        .read(codexChatControllerProvider(widget.tab.id))
        .activeCwd
        ?.trim();
    return cwd == null || cwd.isEmpty ? widget.workspace.path : cwd;
  }

  Future<void> _addPathAttachments(
    Iterable<String> paths, {
    CodexInputAttachmentOrigin origin = CodexInputAttachmentOrigin.attachment,
    String? tokenText,
    int? tokenStart,
  }) async {
    final originatingTabId = widget.tab.id;
    final candidates = <String>[];
    final seen = <String>{};
    for (final rawPath in paths) {
      final path = rawPath.trim();
      if (path.isEmpty || !seen.add(p.normalize(path))) continue;
      candidates.add(path);
    }
    final additions = <CodexInputAttachment>[];
    _setDraftState(() {
      final existing = _attachments
          .map((item) => p.normalize(item.path))
          .toSet();
      for (final path in candidates) {
        if (!existing.add(p.normalize(path))) continue;
        final attachment = CodexInputAttachment(
          id: const Uuid().v4(),
          path: path,
          displayName: p.basename(path),
          isImage: isCodexImagePath(path),
          origin: origin,
          tokenText: tokenText,
          tokenStart: tokenStart,
        );
        additions.add(attachment);
        _attachments.add(attachment);
      }
    });
    if (additions.isEmpty) return;
    _composerFocus.requestFocus();
    final classified = await Future.wait(
      additions.map((attachment) async {
        final isDirectory = await codexAttachmentPathIsDirectory(
          attachment.path,
        );
        return (id: attachment.id, isDirectory: isDirectory);
      }),
    );
    if (!mounted || widget.tab.id != originatingTabId || classified.isEmpty) {
      return;
    }
    final directoryById = <String?, bool>{
      for (final item in classified) item.id: item.isDirectory,
    };
    if (!_attachments.any(
      (attachment) => directoryById.containsKey(attachment.id),
    )) {
      return;
    }
    _setDraftState(() {
      for (var index = 0; index < _attachments.length; index++) {
        final attachment = _attachments[index];
        final isDirectory = directoryById[attachment.id];
        if (isDirectory == null || isDirectory == attachment.isDirectory) {
          continue;
        }
        _attachments[index] = attachment.copyWith(isDirectory: isDirectory);
      }
    });
  }

  Future<void> _rename(
    BuildContext context,
    CodexChatController controller,
  ) async {
    final threadTitle = ref
        .read(codexChatControllerProvider(widget.tab.id))
        .snapshot
        .title;
    final input = TextEditingController(
      text: threadTitle?.trim().isNotEmpty == true
          ? threadTitle!.trim()
          : widget.tab.title,
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Codex Thread'),
        content: TextField(
          controller: input,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name != null) await controller.rename(name);
  }

  Future<void> _pickCatalog(
    BuildContext context,
    List<Map<String, Object?>> items, {
    required bool skill,
  }) async {
    if (items.isEmpty) return;
    final selected = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _CodexCatalogPickerDialog(
        title: skill ? 'Select A Skill' : 'Select An App',
        items: items,
        searchHint: skill ? 'Filter Skills' : 'Filter Apps',
      ),
    );
    if (selected == null) return;
    final name = _catalogName(selected);
    final path = skill
        ? selected['path']?.toString().trim()
        : _catalogConnector(selected);
    if (path == null || path.isEmpty) return;
    _addDraftItem(
      CodexDraftItem(
        id: '${skill ? 'skill' : 'app'}-$path',
        kind: skill ? CodexDraftItemKind.skill : CodexDraftItemKind.app,
        name: name,
        path: path,
        tokenText: skill ? null : '\$$name',
        iconUrl: skill ? null : _catalogIconUrl(selected),
      ),
    );
  }

  Future<void> _openAttachment(
    String filePath, {
    required bool isImage,
    int? line,
  }) async {
    final activeWorkspacePath = _activeCodexWorkspacePath;
    final resolvedFilePath = p.normalize(
      p.isAbsolute(filePath) ? filePath : p.join(activeWorkspacePath, filePath),
    );
    final attachmentWorkspace = codexWorkspaceForFile(
      workspaces: ref
          .read(workbenchControllerProvider)
          .workspacesByProject
          .values
          .expand((workspaces) => workspaces),
      filePath: resolvedFilePath,
    );
    if (attachmentWorkspace == null) {
      await _openExternalAttachment(resolvedFilePath, isImage: isImage);
      return;
    }
    final openedInAlera = await openTerminalComposerWorkspaceAttachment(
      workspacePath: attachmentWorkspace.path,
      filePath: resolvedFilePath,
      workspaceFiles: _workspaceFiles,
      openFile: (relativePath) async {
        if (!mounted) return;
        final workbench = ref.read(workbenchControllerProvider.notifier);
        final previewKind = workspaceFilePreviewKindForPath(relativePath);
        final revealInEditor =
            line != null &&
            previewKind != WorkspaceFilePreviewKind.image &&
            previewKind != WorkspaceFilePreviewKind.pdf;
        final tab = revealInEditor
            ? await workbench.openEditorTab(
                workspace: attachmentWorkspace,
                relativePath: relativePath,
              )
            : await workbench.openFileTab(
                workspace: attachmentWorkspace,
                relativePath: relativePath,
              );
        if (!mounted) return;
        await workbench.selectWorkspaceTab(
          workspaceId: attachmentWorkspace.id,
          tabId: tab.id,
        );
        if (!mounted) return;
        if (line != null && tab.kind == WorkspaceTabKind.editor) {
          ref
              .read(editorSessionRegistryProvider)
              .reveal(
                tab.id,
                WorkspaceEditorRevealTarget(
                  line: line,
                  column: 1,
                  matchLength: 0,
                ),
              );
        }
      },
    );
    if (openedInAlera || !mounted) return;
    await _openExternalAttachment(resolvedFilePath, isImage: isImage);
  }

  Future<void> _openExternalAttachment(
    String resolvedFilePath, {
    required bool isImage,
  }) async {
    if (!mounted) return;
    if (isImage) {
      await _showCodexImagePreview(context, resolvedFilePath);
      return;
    }
    try {
      final opened = await launchUrl(
        Uri.file(resolvedFilePath),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) _showMarkdownLinkError();
    } catch (_) {
      _showMarkdownLinkError();
    }
  }

  Future<void> _send(CodexChatController controller) async {
    final state = ref.read(codexChatControllerProvider(widget.tab.id));
    if (await _runTypedSessionCommand(controller, state)) {
      if (mounted) _composerFocus.requestFocus();
      return;
    }
    final text = _expandSavedPrompt(_composer.text);
    final attachments = List<CodexInputAttachment>.of(_attachments);
    final draftItems = List<CodexDraftItem>.of(_draftItems);
    _composer.clear();
    _setDraftState(() {
      _attachments.clear();
      _draftItems.clear();
    });
    await controller.send(
      text,
      attachments: attachments,
      draftItems: draftItems,
    );
    if (mounted) _composerFocus.requestFocus();
  }

  Future<bool> _runTypedSessionCommand(
    CodexChatController controller,
    CodexChatState state,
  ) async {
    if (_attachments.isNotEmpty || _draftItems.isNotEmpty) return false;
    final match = RegExp(
      r'^/(rename|new|clear|resume)(?:\s+(.+))?$',
      caseSensitive: false,
    ).firstMatch(_composer.text.trim());
    if (match == null) return false;
    final command = match.group(1)!.toLowerCase();
    final argument = match.group(2)?.trim();
    if (_savedPrompts.any((prompt) => prompt.name.toLowerCase() == command)) {
      return false;
    }
    if (!state.supportsSessions) {
      if (command == 'resume') return false;
      if (command == 'new' || command == 'clear') {
        _composer.clear();
        await _openLegacyCodexTab();
        return true;
      }
    }
    if (command == 'resume' && argument != null && argument.isNotEmpty) {
      return false;
    }
    _composer.clear();
    switch (command) {
      case 'rename':
        if (argument == null || argument.isEmpty) {
          await _rename(context, controller);
        } else {
          await controller.rename(argument);
        }
      case 'new':
        final succeeded = await controller.newThread();
        if (succeeded && argument != null && argument.isNotEmpty) {
          await controller.rename(argument);
        }
      case 'clear':
        final succeeded = await controller.clearThread();
        if (succeeded && argument != null && argument.isNotEmpty) {
          await controller.rename(argument);
        }
      case 'resume':
        await _resumeThread(context, controller, state);
    }
    return true;
  }

  void _editQueued(
    CodexChatController controller,
    int index,
    CodexQueuedMessage message,
  ) {
    if (_composer.text.isNotEmpty ||
        _attachments.isNotEmpty ||
        _draftItems.isNotEmpty) {
      AleraToast.show(
        context,
        message: 'Clear the current draft before editing a queued message.',
      );
      return;
    }
    controller.removeQueuedMessage(index);
    _composer.value = TextEditingValue(
      text: message.text,
      selection: TextSelection.collapsed(offset: message.text.length),
    );
    _setDraftState(() {
      _attachments
        ..clear()
        ..addAll(message.attachments);
      _draftItems
        ..clear()
        ..addAll(message.draftItems);
    });
    _composerFocus.requestFocus();
  }
}

@visibleForTesting
Future<bool> codexAttachmentPathIsDirectory(String path) async {
  try {
    return await FileSystemEntity.type(path, followLinks: true) ==
        FileSystemEntityType.directory;
  } catch (_) {
    return false;
  }
}

@visibleForTesting
Workspace? codexWorkspaceForFile({
  required Iterable<Workspace> workspaces,
  required String filePath,
}) {
  final normalizedFilePath = p.normalize(filePath);
  Workspace? match;
  var matchLength = -1;
  for (final workspace in workspaces) {
    if (!workspace.isActive) continue;
    final workspacePath = p.normalize(workspace.path);
    if (!p.equals(workspacePath, normalizedFilePath) &&
        !p.isWithin(workspacePath, normalizedFilePath)) {
      continue;
    }
    if (workspacePath.length > matchLength) {
      match = workspace;
      matchLength = workspacePath.length;
    }
  }
  return match;
}
