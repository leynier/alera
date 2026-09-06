part of 'workspace_workbench_view.dart';

class const _WorkspaceTabContent({
  required final Workspace workspace,
  required final WorkspaceSourceControlScope? sourceControlScope,
  required final WorkspaceTabRecord tab,
  required final bool autofocus,
  required final TerminalRuntime terminalRuntime,
  required final WorkbenchMobileDriverPresence? mobileDriverPresence,
  required final ValueChanged<String> onOpenEditorTab,
  required final ValueChanged<String> onOpenMarkdownViewerTab,
  required final ValueChanged<String> onOpenMermanPreview,
}) extends StatelessWidget {
  Widget _buildTerminal() {
    final surface = TerminalSurface(
      session: terminalRuntime.sessionFor(workspace: workspace, tab: tab),
      autofocus: autofocus,
    );
    final presence = mobileDriverPresence;
    final driver = presence?.drivers[tab.terminalSessionId];
    if (presence == null || driver == null) {
      return surface;
    }
    // The phone drives this viewport: block desktop interaction but keep the
    // output visible under the overlay banner.
    return Stack(
      fit: .expand,
      children: <Widget>[
        IgnorePointer(child: surface),
        MobileDriverOverlay(
          deviceName: driver.deviceName ?? 'A Phone',
          drivenCount: presence.drivers.length,
          onTakeBack: () => presence.onReclaim(tab.terminalSessionId),
          onTakeBackAll: presence.onReclaimAll,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (tab.kind) {
      WorkspaceTabKind.terminal => _buildTerminal(),
      WorkspaceTabKind.editor => _WorkspaceFileTabContent(
        workspace: workspace,
        sourceControlScope: sourceControlScope,
        tab: tab,
        autofocus: autofocus,
        onOpenEditor: onOpenEditorTab,
        onOpenMermanPreview: onOpenMermanPreview,
        onOpenMarkdownViewerTab: onOpenMarkdownViewerTab,
      ),
      WorkspaceTabKind.markdownViewer => WorkspaceMarkdownViewerSurface(
        workspace: workspace,
        tab: tab,
        onOpenEditorTab: onOpenEditorTab,
      ),
      WorkspaceTabKind.pdf => WorkspacePdfViewerSurface(
        workspace: workspace,
        tab: tab,
        autofocus: autofocus,
      ),
      WorkspaceTabKind.gitDiff => WorkspaceGitDiffSurface(
        workspace: workspace,
        tab: tab,
      ),
    };
  }
}

class const _WorkspaceFileTabContent({
  required final Workspace workspace,
  required final WorkspaceSourceControlScope? sourceControlScope,
  required final WorkspaceTabRecord tab,
  required final bool autofocus,
  required final ValueChanged<String> onOpenEditor,
  required final ValueChanged<String> onOpenMermanPreview,
  required final ValueChanged<String> onOpenMarkdownViewerTab,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final filePath = tab.filePath;
    if (filePath != null && isWorkspaceImageFilePath(filePath)) {
      return WorkspaceImagePreviewSurface(
        workspace: workspace,
        tab: tab,
        autofocus: autofocus,
      );
    }
    if (filePath != null &&
        tab.isMermanPreview &&
        isWorkspaceMermanFilePath(filePath)) {
      return WorkspaceMermanViewerSurface(
        workspace: workspace,
        tab: tab,
        autofocus: autofocus,
        onOpenEditor: onOpenEditor,
      );
    }
    return WorkspaceEditorSurface(
      workspace: workspace,
      sourceControlScope: sourceControlScope,
      tab: tab,
      autofocus: autofocus,
      onOpenMermanPreview: onOpenMermanPreview,
      onOpenMarkdownViewerTab: onOpenMarkdownViewerTab,
      onKeepPreview: tab.isPreview
          ? () => _KeepPreviewTabScope.maybeOf(context)?.call(tab.id)
          : null,
    );
  }
}
