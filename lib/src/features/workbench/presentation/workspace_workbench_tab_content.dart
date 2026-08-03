part of 'workspace_workbench_view.dart';

class _WorkspaceTabContent extends StatelessWidget {
  const _WorkspaceTabContent({
    required this.workspace,
    required this.sourceControlScope,
    required this.tab,
    required this.autofocus,
    required this.terminalRuntime,
    required this.mobileDriverPresence,
    required this.onOpenEditorTab,
    required this.onOpenMarkdownViewerTab,
    required this.onOpenMermanPreview,
  });

  final Workspace workspace;
  final WorkspaceSourceControlScope? sourceControlScope;
  final WorkspaceTabRecord tab;
  final bool autofocus;
  final TerminalRuntime terminalRuntime;
  final WorkbenchMobileDriverPresence? mobileDriverPresence;
  final ValueChanged<String> onOpenEditorTab;
  final ValueChanged<String> onOpenMarkdownViewerTab;
  final ValueChanged<String> onOpenMermanPreview;

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
      fit: StackFit.expand,
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
      WorkspaceTabKind.codex => CodexChatSurface(
        workspace: workspace,
        tab: tab,
        autofocus: autofocus,
      ),
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
      WorkspaceTabKind.browser => BrowserTabSurface(
        tab: tab,
        autofocus: autofocus,
        pageObscured: _WorkbenchTabDragScope.isActiveOf(context),
      ),
      WorkspaceTabKind.mobileEmulator => MobileEmulatorSurface(
        workspace: workspace,
        tab: tab,
        autofocus: autofocus,
      ),
    };
  }
}

class _WorkspaceFileTabContent extends StatelessWidget {
  const _WorkspaceFileTabContent({
    required this.workspace,
    required this.sourceControlScope,
    required this.tab,
    required this.autofocus,
    required this.onOpenEditor,
    required this.onOpenMermanPreview,
    required this.onOpenMarkdownViewerTab,
  });

  final Workspace workspace;
  final WorkspaceSourceControlScope? sourceControlScope;
  final WorkspaceTabRecord tab;
  final bool autofocus;
  final ValueChanged<String> onOpenEditor;
  final ValueChanged<String> onOpenMermanPreview;
  final ValueChanged<String> onOpenMarkdownViewerTab;

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
    );
  }
}
