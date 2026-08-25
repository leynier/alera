part of 'workspace_tab_service.dart';

WorkspaceTabRecord? _previewTabToReplace(
  List<WorkspaceTabRecord> existing,
  String? replacePreviewTabId,
) {
  if (replacePreviewTabId == null) {
    return null;
  }
  for (final tab in existing) {
    if (tab.id == replacePreviewTabId && tab.isFilePreviewSlot) {
      return tab;
    }
  }
  return null;
}

/// Opening file-backed tabs, including one replaceable preview slot per open.
extension WorkspaceTabFileOpening on WorkspaceTabService {
  Future<WorkspaceTabRecord> openOrCreateEditorTab({
    required String workspaceId,
    required String relativePath,
    bool preview = false,
    String? replacePreviewTabId,
  }) {
    return _openOrCreateFileTab(
      workspaceId: workspaceId,
      relativePath: relativePath,
      kind: WorkspaceTabKind.editor,
      preview: preview,
      replacePreviewTabId: replacePreviewTabId,
    );
  }

  Future<WorkspaceTabRecord> openOrCreatePdfTab({
    required String workspaceId,
    required String relativePath,
    bool preview = false,
    String? replacePreviewTabId,
  }) {
    return _openOrCreateFileTab(
      workspaceId: workspaceId,
      relativePath: relativePath,
      kind: WorkspaceTabKind.pdf,
      preview: preview,
      replacePreviewTabId: replacePreviewTabId,
    );
  }

  Future<WorkspaceTabRecord> openOrCreateMarkdownViewerTab({
    required String workspaceId,
    required String relativePath,
    bool preview = false,
    String? replacePreviewTabId,
  }) async {
    final normalizedPath = _normalizeRelativePath(relativePath);
    if (!isWorkspaceMarkdownFilePath(normalizedPath)) {
      throw StateError('Markdown viewer tabs require a .md file');
    }
    return _openOrCreateFileTab(
      workspaceId: workspaceId,
      relativePath: normalizedPath,
      kind: WorkspaceTabKind.markdownViewer,
      preview: preview,
      replacePreviewTabId: replacePreviewTabId,
    );
  }

  Future<WorkspaceTabRecord> keepPreviewTab(String tabId) async {
    final tab = await _repository.findWorkspaceTabById(tabId);
    if (tab == null) {
      throw StateError('Workspace tab not found: $tabId');
    }
    if (!tab.isPreview) {
      return tab;
    }
    final payload = Map<String, Object?>.of(tab.payload)
      ..remove(workspaceTabPreviewPayloadKey);
    final next = tab.copyWith(updatedAt: _now(), payload: payload);
    await _repository.upsertWorkspaceTab(next);
    return next;
  }

  Future<WorkspaceTabRecord> _openOrCreateFileTab({
    required String workspaceId,
    required String relativePath,
    required WorkspaceTabKind kind,
    bool preview = false,
    String? replacePreviewTabId,
  }) async {
    final normalizedPath = _normalizeRelativePath(relativePath);
    final existing = await _repository.listWorkspaceTabs(workspaceId);
    for (final tab in existing) {
      if (tab.isMermanPreview ||
          tab.payload[workspaceTabFilePathPayloadKey] != normalizedPath) {
        continue;
      }
      if (tab.kind == kind) {
        if (!preview && tab.isPreview) {
          return keepPreviewTab(tab.id);
        }
        return tab;
      }
      if (!_canRetargetFileBackedTab(from: tab.kind, to: kind)) {
        continue;
      }
      final payload = <String, Object?>{
        ...tab.payload,
        workspaceTabFilePathPayloadKey: normalizedPath,
      };
      if (preview) {
        payload[workspaceTabPreviewPayloadKey] = true;
      } else {
        payload.remove(workspaceTabPreviewPayloadKey);
      }
      final next = tab.copyWith(
        kind: kind,
        updatedAt: _now(),
        payload: payload,
      );
      await _repository.upsertWorkspaceTab(next);
      return next;
    }
    if (preview) {
      final replace = _previewTabToReplace(existing, replacePreviewTabId);
      if (replace != null) {
        final next = replace.copyWith(
          kind: kind,
          title: _titleForPath(normalizedPath),
          updatedAt: _now(),
          payload: <String, Object?>{
            workspaceTabFilePathPayloadKey: normalizedPath,
            workspaceTabPreviewPayloadKey: true,
          },
        );
        await _repository.upsertWorkspaceTab(next);
        return next;
      }
    }
    final tab = WorkspaceTabRecord(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      kind: kind,
      title: _titleForPath(normalizedPath),
      createdAt: _now(),
      updatedAt: _now(),
      payload: <String, Object?>{
        workspaceTabFilePathPayloadKey: normalizedPath,
        if (preview) workspaceTabPreviewPayloadKey: true,
      },
    );
    await _repository.upsertWorkspaceTab(tab);
    return tab;
  }

  bool _canRetargetFileBackedTab({
    required WorkspaceTabKind from,
    required WorkspaceTabKind to,
  }) {
    return switch ((from, to)) {
      (WorkspaceTabKind.editor, WorkspaceTabKind.pdf) ||
      (WorkspaceTabKind.pdf, WorkspaceTabKind.editor) => true,
      _ => false,
    };
  }
}
