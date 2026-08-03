import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/workbench/application/terminal_composer_workspace_attachment.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

TerminalComposer buildTerminalComposerForWorkspace(
  WidgetRef ref,
  TerminalSessionHandle session,
) {
  return TerminalComposer(
    session: session,
    onOpenWorkspaceFile: (filePath) =>
        openTerminalComposerWorkspaceFile(ref, session.workspaceId, filePath),
  );
}

Future<bool> openTerminalComposerWorkspaceFile(
  WidgetRef ref,
  String workspaceId,
  String filePath,
) async {
  final workspace = findWorkspaceById(
    ref.read(workbenchControllerProvider),
    workspaceId,
  );
  if (workspace == null) {
    return false;
  }
  return openTerminalComposerWorkspaceAttachment(
    workspacePath: workspace.path,
    filePath: filePath,
    workspaceFiles: ref.read(workspaceFileServiceProvider),
    openFile: (relativePath) => ref
        .read(workbenchControllerProvider.notifier)
        .openFileTab(workspace: workspace, relativePath: relativePath),
  );
}
