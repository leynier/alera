import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_compose_delivery.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_prompt.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_target.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_agent_comment_controller.g.dart';

/// Draft file comments for one workspace, held in memory like the desktop
/// queue. `keepAlive` so switching panels does not discard them.
@Riverpod(keepAlive: true)
class WorkspaceAgentCommentController
    extends _$WorkspaceAgentCommentController {
  int _nextId = 0;

  @override
  List<WorkspaceAgentComment> build(String hostId, String workspaceId) =>
      const <WorkspaceAgentComment>[];

  void add({required String path, required String body, String? snippet}) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _nextId += 1;
    state = <WorkspaceAgentComment>[
      ...state,
      WorkspaceAgentComment(
        id: 'comment-$_nextId',
        path: path,
        body: trimmed,
        snippet: capWorkspaceAgentCommentSnippet(snippet),
      ),
    ];
  }

  void remove(String id) {
    state = <WorkspaceAgentComment>[
      for (final comment in state)
        if (comment.id != id) comment,
    ];
  }

  void clear() => state = const <WorkspaceAgentComment>[];

  /// Delivers every queued comment as one prompt and returns the tab that
  /// received it. The queue is cleared only after the host accepted the
  /// prompt, so a failed send keeps the comments for a retry.
  Future<String> sendTo(WorkspaceAgentCommentTarget target) async {
    final prompt = workspaceAgentCommentPrompt(state);
    if (prompt.isEmpty) {
      throw StateError('Add a comment before sending.');
    }
    final tabId = switch (target) {
      RunningAgentCommentTarget(:final agent) => await _writeToRunningAgent(
        agent.terminalSessionId,
        prompt,
      ).then((_) => agent.tabId),
      AgentProfileCommentTarget(:final profile) =>
        await ref
            .read(tabsControllerProvider(hostId, workspaceId).notifier)
            .launchAgentProfileTab(profile.id, prompt: prompt),
    };
    clear();
    return tabId;
  }

  // The host accepts a write for any live session, attached or not, so this
  // needs no attach. The Enter goes through the same deferred path as the
  // terminal composer, or an agent TUI reads it as a newline in the paste.
  Future<void> _writeToRunningAgent(String sessionId, String prompt) async {
    final client = await ref.read(terminalClientProvider(hostId).future);
    final delivery = TerminalComposeDelivery.forText(
      prompt,
      withEnter: true,
      hostSupportsDeferredInput: client.supportsDeferredTerminalInput,
    );
    await client.writeTerminal(
      sessionId,
      delivery.bytes,
      bracketedPaste: delivery.bracketedPaste,
      deferredEnter: delivery.deferredEnter,
    );
  }
}
