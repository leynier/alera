import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_plan_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_question_dock.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_status_views.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_notice.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything under the conversation: problems and the way out of them, the
/// runtime's queue, the plan in progress, open questions, and the composer.
class const AgentChatFooter({
  super.key,
  required final String chatId,
  required final Workspace workspace,
  required final String fallbackProvider,
  required final TerminalComposerController composer,
  required final ValueChanged<String> onOpenFile,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = agentChatControllerProvider(chatId, workspace.id);
    final view = ref.watch(
      provider.select(
        (state) => (
          actionError: state.actionError,
          live: state.live,
          recovery: state.thread?.recovery,
          recovering: state.recovering,
          queue: state.thread?.queue ?? const <AgentChatQueueEntry>[],
          cancelling: state.cancellingQueueIds,
          planSteps: state.projection?.activePlanSteps,
          busy: state.busy,
          requests: state.thread?.pendingRequests ?? const <AgentChatRequest>[],
          responding: state.respondingRequestIds,
          canSend: state.canSend,
          canInterrupt: state.canInterrupt,
          interrupting: state.interrupting,
          configuring: state.configuring,
          canSwitchProvider: state.canSwitchProvider,
          archived: state.archived,
          session: state.thread?.session,
          provider: state.thread?.provider ?? '',
          providerInstanceId: state.thread?.providerInstanceId ?? '',
          usage: state.thread?.usage ?? const AgentChatUsage(),
        ),
      ),
    );
    final controller = ref.read(provider.notifier);
    final catalog = ref
        .watch(agentChatProviderCatalogProvider(workspace.id))
        .value;
    final session = view.session ?? const AgentChatSession();
    final settings = AgentChatComposerSettings(
      provider: view.provider.isEmpty ? fallbackProvider : view.provider,
      providerInstanceId: view.providerInstanceId,
      session: session,
      providers: catalog ?? const <AgentChatProviderInstance>[],
      canSwitchProvider: view.canSwitchProvider,
      configuring: view.configuring,
    );
    final questions = <AgentChatRequest>[
      for (final request in view.requests)
        if (request.isQuestion) request,
    ];
    final docks = <Widget>[
      if (view.actionError case final String error)
        AgentChatActionErrorBanner(
          message: error,
          onDismiss: controller.dismissError,
        ),
      if (!view.live) const AgentChatReconnectingBanner(),
      if (view.recovery case final AgentChatRecovery recovery when !view.busy)
        AgentChatRecoveryNotice(
          recovery: recovery,
          recovering: view.recovering,
          onResume: () =>
              unawaited(controller.recover(AgentChatRecoverMode.resume)),
          onRestart: () =>
              unawaited(controller.recover(AgentChatRecoverMode.restart)),
        ),
      if (view.queue.isNotEmpty)
        AgentChatQueueDock(
          queue: view.queue,
          cancellingQueueIds: view.cancelling,
          onCancel: (queueId) => unawaited(controller.cancelQueued(queueId)),
        ),
      if (view.planSteps case final AgentChatItem steps when view.busy)
        AgentChatPlanProgressDock(item: steps),
      if (questions.isNotEmpty)
        AgentChatQuestionDock(
          key: ValueKey<String>('agent-chat-questions-$chatId'),
          chatId: chatId,
          requests: questions,
          respondingRequestIds: view.responding,
          enabled: view.live,
          onRespond: controller.respond,
        ),
      if (view.archived)
        const AleraInlineNotice(
          message:
              'This chat is archived. Its history stays on the runtime; '
              'reopen it from New Agent Chat to continue.',
        ),
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.agentChatConversationMaxWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Hides itself on runtimes without chat tasks or with none open,
            // so it sits outside the spaced docks.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
              ),
              child: ChatTasksForChat(chatId: chatId),
            ),
            if (docks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AleraTokens.space12,
                  AleraTokens.space8,
                  AleraTokens.space12,
                  0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AleraTokens.space8,
                  children: docks,
                ),
              ),
            if (!view.archived)
              AgentChatComposer(
                controller: composer,
                workspaceId: workspace.id,
                chatId: chatId,
                settings: catalog == null ? null : settings,
                usage: view.usage,
                canSend: view.canSend,
                busy: view.busy,
                canInterrupt: view.canInterrupt,
                interrupting: view.interrupting,
                hintText: !view.live
                    ? 'Reconnecting to the Alera runtime'
                    : view.busy
                    ? 'Send a message to queue it after this turn'
                    : 'Ask ${settings.providerLabel} anything',
                promptHistory: () =>
                    ref.read(provider).projection?.promptHistory ??
                    const <String>[],
                onSend: (text, attachments) =>
                    controller.send(text, attachments: attachments),
                onInterrupt: () => unawaited(controller.interrupt()),
                onConfigure: (configuration) =>
                    unawaited(controller.configure(configuration)),
                onOpenFile: onOpenFile,
              ),
          ],
        ),
      ),
    );
  }
}
