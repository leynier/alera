part of 'alera_shell_page.dart';

bool _oppositePanelOpenRequested() => isModModifierPressed();

extension _AleraShellPageBodyTools on _AleraShellPageBodyState {
  Widget Function(WorkbenchContextPanelTab tab) _workspaceToolFactory({
    required Workspace workspace,
    required WorkbenchViewPrefs prefs,
    required WorkspaceSourceControlScope? sourceControlScope,
    required bool canSelectSourceControlRoot,
  }) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    return (tab) {
      final sourceKey = switch (tab) {
        WorkbenchContextPanelTab.explorer => WorkspaceTool.explorer.key,
        WorkbenchContextPanelTab.search => WorkspaceTool.search.key,
        WorkbenchContextPanelTab.gitDiff => WorkspaceTool.sourceControl.key,
        WorkbenchContextPanelTab.pullRequests => WorkspaceTool.pullRequest.key,
      };

      return WorkspaceContextSidebar.toolFor(
        tab: tab,
        workspace: workspace,
        prefs: prefs,
        sourceControlScope: sourceControlScope,
        focusedSourceControlRoot: canSelectSourceControlRoot
            ? prefs.sourceControlRootByWorkspaceId[workspace.id]
            : null,
        onSetExplorerMode: controller.setExplorerMode,
        onSetGitDiffViewMode: controller.setGitDiffViewMode,
        onSetGitDiffGroupMode: controller.setGitDiffGroupMode,
        onSetSearchViewAsTree: controller.setSearchViewAsTree,
        onSetSearchIncludeIgnored: controller.setSearchIncludeIgnored,
        onFocusSourceControlFolder: canSelectSourceControlRoot
            ? (relativePath) {
                return controller.focusSourceControlFolder(
                  workspace: workspace,
                  relativePath: relativePath,
                );
              }
            : null,
        onClearSourceControlRoot: canSelectSourceControlRoot
            ? () {
                controller.clearFocusedSourceControlFolder(
                  workspace: workspace,
                );
              }
            : null,
        onOpenFile: (relativePath) {
          unawaited(
            controller.openFileTab(
              workspace: workspace,
              sourceKey: sourceKey,
              relativePath: relativePath,
              preview: true,
              oppositePanel: _oppositePanelOpenRequested(),
            ),
          );
        },
        onOpenFilePermanently: (relativePath) {
          unawaited(
            controller.openFileTab(
              workspace: workspace,
              sourceKey: sourceKey,
              relativePath: relativePath,
              oppositePanel: _oppositePanelOpenRequested(),
            ),
          );
        },
        onRevealInExplorer: (relativePath) {
          controller.revealInExplorer(
            workspace: workspace,
            relativePath: relativePath,
          );
        },
        onOpenGitDiff:
            ({
              relativePath,
              area,
              gitDiffRoot,
              required scope,
              preview = false,
              oppositePanel = false,
            }) {
              return controller.openGitDiffTab(
                workspace: workspace,
                sourceKey: sourceKey,
                relativePath: relativePath,
                area: area,
                scope: scope,
                gitDiffRoot: gitDiffRoot,
                preview: preview,
                oppositePanel: oppositePanel,
              );
            },
        onOpenGitCommitDiff:
            ({
              relativePath,
              oldPath,
              required scope,
              gitDiffRoot,
              required commitOid,
              parentOid,
              required compareRef,
              subject,
              message,
              preview = false,
              oppositePanel = false,
            }) {
              return controller.openGitCommitDiffTab(
                workspace: workspace,
                sourceKey: sourceKey,
                relativePath: relativePath,
                oldPath: oldPath,
                scope: scope,
                gitDiffRoot: gitDiffRoot,
                commitOid: commitOid,
                parentOid: parentOid,
                compareRef: compareRef,
                subject: subject,
                message: message,
                preview: preview,
                oppositePanel: oppositePanel,
              );
            },
        onOpenSearchMatch: (target) {
          unawaited(() async {
            final tab = await controller.openEditorTab(
              workspace: workspace,
              sourceKey: sourceKey,
              relativePath: target.relativePath,
              preview: true,
              oppositePanel: _oppositePanelOpenRequested(),
            );
            ref
                .read(editorSessionRegistryProvider)
                .reveal(
                  tab.id,
                  WorkspaceEditorRevealTarget(
                    line: target.line,
                    column: target.column,
                    matchLength: target.matchLength,
                  ),
                );
          }());
        },
        onPathMoved: (oldRelativePath, newRelativePath) async {
          await controller.syncFileTabsAfterPathMove(
            workspace: workspace,
            oldRelativePath: oldRelativePath,
            newRelativePath: newRelativePath,
          );
          ref
              .read(editorSessionRegistryProvider)
              .updateDocumentPathsAfterMove(
                workspacePath: workspace.path,
                oldRelativePath: oldRelativePath,
                newRelativePath: newRelativePath,
              );
          controller.syncSourceControlRootAfterPathMove(
            workspace: workspace,
            oldRelativePath: oldRelativePath,
            newRelativePath: newRelativePath,
          );
        },
      );
    };
  }

  void _showError(String message) {
    AleraToast.show(context, message: message, tone: .error);
  }
}
