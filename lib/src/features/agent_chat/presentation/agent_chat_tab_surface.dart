import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_relationships.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_relationships_control.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_relationships_panel.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_status_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_subagent_scope.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_subagent_surface.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_open_actions.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_action_scope_region.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The workbench content of an `agentChat` tab: the chat, or one of its
/// provider-native sub-agents opened in its place, and the lineage control.
class const AgentChatTabSurface({
  super.key,
  required final Workspace workspace,
  required final WorkspaceTabRecord tab,
  final bool autofocus = false,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatTabSurface> createState() =>
      _AgentChatTabSurfaceState();
}

class _AgentChatTabSurfaceState extends ConsumerState<AgentChatTabSurface> {
  Set<String> _stopping = const <String>{};
  bool _merging = false;

  AgentChatRef _chat(String chatId) =>
      AgentChatRef(chatId: chatId, workspaceId: widget.workspace.id);

  Future<void> _stop(String chatId, String callId) async {
    setState(() => _stopping = <String>{..._stopping, callId});
    try {
      await ref
          .read(agentChatLifecycleRepositoryProvider)
          .stopSubagent(
            _chat(chatId),
            requestId: ref.read(agentChatIdGeneratorProvider)(),
            itemId: callId,
          );
    } on Object catch (error) {
      AleraToast.publish(
        message:
            'Could not stop the sub-agent: ${agentChatErrorMessage(error)}',
        tone: .error,
      );
    } finally {
      if (mounted) {
        setState(() => _stopping = <String>{..._stopping}..remove(callId));
      }
    }
  }

  Future<void> _mergeBack(String chatId, AgentChatRelation target) async {
    setState(() => _merging = true);
    try {
      await ref
          .read(agentChatLifecycleRepositoryProvider)
          .mergeBack(
            _chat(chatId),
            requestId: ref.read(agentChatIdGeneratorProvider)(),
          );
      AleraToast.publish(
        message:
            'Merged into ${target.title}. Its agent reads the work with the '
            'next message.',
      );
    } on Object catch (error) {
      AleraToast.publish(
        message: 'Could not merge back: ${agentChatErrorMessage(error)}',
        tone: .error,
      );
    } finally {
      if (mounted) setState(() => _merging = false);
    }
  }

  void _openChat(String relatedChatId) {
    final chats = ref.read(agentChatRelatedChatsProvider).value;
    final summary = chats
        ?.where((chat) => chat.chatId == relatedChatId)
        .firstOrNull;
    if (summary == null) return;
    unawaited(
      openChatTaskChat(
        context,
        ref,
        chatId: relatedChatId,
        workspaceId: summary.workspaceId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chatId = widget.tab.agentChatId;
    if (chatId == null) return const AgentChatUnboundView();
    final open = agentChatOpenSubagentProvider(chatId);
    final openCall = ref.watch(open);
    bool capability(String name) =>
        ref.watch(agentChatCapabilityProvider(name)).value ?? false;
    final threads = capability(AgentChatWire.subagentThreadsCapability);
    final mergeBack = capability(AgentChatWire.mergeBackCapability);
    final stopSupported = ref.watch(
      agentChatControllerProvider(chatId, widget.workspace.id).select(
        (state) => state.thread?.session.capabilities.stopSubagent ?? false,
      ),
    );
    final idle = ref.watch(
      agentChatControllerProvider(
        chatId,
        widget.workspace.id,
      ).select((state) => state.thread?.session.activeTurnId == null),
    );
    final onOpen = threads ? ref.read(open.notifier).open : null;
    final onStop = threads && stopSupported
        ? (String callId) => unawaited(_stop(chatId, callId))
        : null;
    // Chat-scoped shortcuts, such as Find in Chat, apply while the focus
    // is anywhere in the chat: the timeline, the find bar or the composer.
    return KeyboardActionScopeRegion(
      scope: KeyboardActionScope.agentChat,
      target: chatId,
      child: AgentChatSubagentScope(
        onOpen: onOpen,
        onStop: onStop,
        stopping: _stopping,
        child: Stack(
          children: <Widget>[
            // The chat stays mounted under an open sub-agent, so its scroll
            // position and composer survive the visit.
            Positioned.fill(
              child: ExcludeFocus(
                excluding: openCall != null,
                child: Offstage(
                  offstage: openCall != null,
                  child: TickerMode(
                    enabled: openCall == null,
                    child: AgentChatSurface(
                      key: ValueKey<String>('agent-chat-surface-$chatId'),
                      chatId: chatId,
                      workspace: widget.workspace,
                      fallbackTitle: widget.tab.title,
                      fallbackProvider: widget.tab.agentChatProvider ?? '',
                      autofocus: widget.autofocus,
                    ),
                  ),
                ),
              ),
            ),
            if (openCall != null)
              Positioned.fill(
                child: AgentChatSubagentSurface(
                  key: ValueKey<String>(
                    'agent-chat-subagent-surface-$openCall',
                  ),
                  chatId: chatId,
                  workspace: widget.workspace,
                  callId: openCall,
                ),
              )
            else
              // Top-left: Find in Chat opens at the top-right.
              Positioned(
                top: AleraTokens.space8,
                left: AleraTokens.space12,
                child: AgentChatRelationshipsControl(
                  chatId: chatId,
                  workspaceId: widget.workspace.id,
                  actions: (relationships, close) =>
                      AgentChatRelationshipActions(
                        onOpenChat: (id) {
                          close();
                          _openChat(id);
                        },
                        onOpenSubagent: onOpen == null
                            ? null
                            : (callId) {
                                close();
                                onOpen(callId);
                              },
                        onStopSubagent: onStop,
                        stopping: _stopping,
                        merging: _merging,
                        onMergeBack:
                            mergeBack &&
                                idle &&
                                relationships.mergeTarget != null
                            ? () => unawaited(
                                _mergeBack(chatId, relationships.mergeTarget!),
                              )
                            : null,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
