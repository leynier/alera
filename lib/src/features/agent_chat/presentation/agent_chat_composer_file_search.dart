import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/terminal_path_drop.dart';
import 'package:alera/src/rust/api/workspace_files.dart' as native;
import 'package:alera_agent_chat/alera_agent_chat.dart';

export 'package:alera_agent_chat/alera_agent_chat.dart'
    show
        AgentChatComposerFileSearch,
        AgentChatComposerFileSearchSession,
        AgentChatComposerMentionSearch;

/// Searches a workspace through the Quick Open index, on its own host for a
/// remote workspace, and attaches the absolute path, as a file dragged in
/// from Explorer or Source Control is.
final class const WorkspaceAgentChatComposerFileSearch({
  required final Workspace workspace,
  required final WorkspaceFileService files,
}) implements AgentChatComposerFileSearch {
  @override
  String get key => '${workspace.id}\n${workspace.path}';

  @override
  Future<AgentChatComposerFileSearchSession> open() async =>
      _WorkspaceFileSearchSession(
        workspace,
        files,
        await files.startWorkspaceQuickOpenSession(workspace: workspace),
      );

  @override
  String attachmentPath(String relativePath) => terminalAbsolutePath(
    rootPath: workspace.path,
    relativePath: relativePath,
  );
}

final class const _WorkspaceFileSearchSession(
  final Workspace workspace,
  final WorkspaceFileService files,
  final native.WorkspaceQuickOpenSession session,
) implements AgentChatComposerFileSearchSession {
  @override
  Future<List<String>> search(String query, {required int limit}) async =>
      <String>[
        for (final match in await files.searchWorkspaceQuickOpenSession(
          workspace: workspace,
          session: session,
          query: query,
          limit: limit,
        ))
          match.relativePath,
      ];

  @override
  Future<void> close() => files.stopWorkspaceQuickOpenSession(
    workspace: workspace,
    session: session,
  );
}
