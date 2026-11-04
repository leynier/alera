import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';

/// The `@` mentions of a chat composer, searched through the host's Quick
/// Open index of the workspace, the same index the Add Attachment sheet's
/// Workspace File source uses.
final class const MobileAgentChatComposerFileSearch({
  required final String hostId,
  required final String workspaceId,
  required final MobileCodexWorkspaceClient client,
}) implements AgentChatComposerFileSearch {
  @override
  String get key => '$hostId\n$workspaceId';

  @override
  Future<AgentChatComposerFileSearchSession> open() async => _QuickOpenSession(
    client,
    await client.startWorkspaceQuickOpen(workspaceId),
  );

  /// Relative on purpose, as for a workspace file picked from the sheet:
  /// the runtime resolves it against the chat's working directory.
  @override
  String attachmentPath(String relativePath) => relativePath;
}

final class const _QuickOpenSession(
  final MobileCodexWorkspaceClient client,
  final MobileWorkspaceQuickOpenSession session,
) implements AgentChatComposerFileSearchSession {
  @override
  Future<List<String>> search(String query, {required int limit}) async =>
      <String>[
        for (final match in await client.searchWorkspaceQuickOpen(
          session,
          query,
          limit: limit,
        ))
          match.relativePath,
      ];

  @override
  Future<void> close() => client.stopWorkspaceQuickOpen(session);
}
