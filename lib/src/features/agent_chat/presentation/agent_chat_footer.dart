import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_file_search.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_footer_actions.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_footer_queue.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_native_history_notice.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_plan_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_queued_edit.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_request_dock.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_shortcut_target.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_status_views.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_settings_launcher.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_dock.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything under the conversation: the chat's tasks, problems and the way
/// out of them, the requests the agent waits on, the runtime's queue, the
/// plan in progress, and the composer.
class const AgentChatFooter({
  super.key,
  required final String chatId,
  required final Workspace workspace,
  required final String fallbackProvider,
  required final TerminalComposerController composer,
  required final ValueChanged<String> onOpenFile,
  final ValueChanged<String>? onOpenLink,
  final AleraPopoverController? pickerController,

  /// A queued message being edited in [composer].
  final AgentChatQueuedEdit? queuedEdit,
  final VoidCallback? onOpenArchived,
  final double? requestDockMaxHeight,

  /// The chat's skills for the composer's `$` menu.
  final AgentChatSkillsLoader? skills,
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
          planSteps: state.projection?.activePlanSteps,
          refiningPlan: agentChatImplementablePlanId(state) != null,
          busy: state.busy,
          requests: state.projection?.requests ?? const <AgentChatRequest>[],
          responding: state.respondingRequestIds,
          canSend: state.canSend,
          canSteer: state.canSteer,
          canInterrupt: state.canInterrupt,
          interrupting: state.interrupting,
          configuring: state.configuring,
          canSwitchProvider: state.canSwitchProvider,
          switchBlockedReason: state.providerSwitchBlockedReason,
          neverSent: state.neverSent,
          pendingModel: state.pendingModel,
          archived: state.archived,
          nativeOperation: state.thread?.pendingNativeOperation,
          reconciling: state.reconcilingNativeOperation,
          session: state.thread?.session,
          provider: state.thread?.provider ?? '',
          providerInstanceId: state.thread?.providerInstanceId ?? '',
          usage: state.thread?.usage ?? const AgentChatUsage(),
        ),
      ),
    );
    final controller = ref.read(provider.notifier);
    ref.listen(provider.select((state) => state.thread?.queue), (_, queue) {
      final loss = queuedEdit?.reconcile(queue ?? const []);
      if (loss case final AgentChatQueuedEditLoss loss
          when loss != AgentChatQueuedEditLoss.none) {
        AleraToast.publish(
          message: loss == AgentChatQueuedEditLoss.kept
              ? 'The message left the queue; your edit is now the draft.'
              : 'The message left the queue before your edit was saved.',
        );
      }
    });
    final catalogProvider = agentChatProviderCatalogProvider(workspace.id);
    final catalog = ref.watch(catalogProvider);
    final hostKey = agentChatHostKey(workspace.hostId);
    final preferences =
        ref.watch(agentChatPreferencesProvider(hostKey)).value ??
        const AgentChatPreferences();
    final settings = AgentChatComposerSettings(
      // A chat without an agent yet has neither field; the tab's provider
      // only fills in for older runtimes that omitted it.
      provider: view.provider.isNotEmpty || view.providerInstanceId.isEmpty
          ? view.provider
          : fallbackProvider,
      providerInstanceId: view.providerInstanceId,
      session: view.session ?? const AgentChatSession(),
      providers: catalog.value ?? const <AgentChatProviderInstance>[],
      canSwitchProvider: view.canSwitchProvider,
      configuring: view.configuring,
      catalog: catalog.hasValue
          ? AgentChatCatalogState.ready
          : catalog.isLoading || !catalog.hasError
          ? AgentChatCatalogState.loading
          : AgentChatCatalogState.failed,
      neverSent: view.neverSent,
      switchBlockedReason: view.switchBlockedReason,
      preferences: preferences,
      pendingModel: view.pendingModel,
    );
    void openProviderSettings() => unawaited(
      openAgentChatProviderSettings(
        context,
        hostId: workspace.hostId,
        providerInstanceId: view.providerInstanceId.isEmpty
            ? null
            : view.providerInstanceId,
      ),
    );
    // A pending approval does not hold the message back: sending answers it.
    final approvalSend = agentChatApprovalSend(view.requests);
    final canSubmit =
        view.nativeOperation == null &&
        settings.hasSelection &&
        !(settings.catalog == AgentChatCatalogState.ready &&
            settings.providerUnavailable);
    final docks = <Widget>[
      if (view.nativeOperation case final AgentChatNativeOperation operation)
        AgentChatNativeOperationNotice(
          operation: operation,
          enabled: view.live,
          busy: view.reconciling,
          onAction: (action) =>
              unawaited(controller.reconcileNativeOperation(action)),
        ),
      if (view.actionError case final String error)
        AgentChatActionErrorBanner(
          message: error,
          onDismiss: controller.dismissError,
        ),
      if (view.recovery case final AgentChatRecovery recovery when !view.busy)
        AgentChatRecoveryNotice(
          recovery: recovery,
          recovering: view.recovering,
          onResume: () =>
              unawaited(controller.recover(AgentChatRecoverMode.resume)),
          onRestart: () =>
              unawaited(controller.recover(AgentChatRecoverMode.restart)),
        ),
      if (!view.live) const AgentChatReconnectingBanner(),
      if (view.requests.isNotEmpty)
        AgentChatRequestDock(
          key: ValueKey<String>('agent-chat-requests-$chatId'),
          chatId: chatId,
          requests: view.requests,
          respondingRequestIds: view.responding,
          enabled: view.live,
          onRespond: controller.respond,
          composer: composer,
          onOpenLink: onOpenLink,
          maxHeight: requestDockMaxHeight,
        ),
      if (view.queue.isNotEmpty)
        AgentChatFooterQueue(
          chatId: chatId,
          workspaceId: workspace.id,
          queue: view.queue,
          canSteer: view.canSteer,
          composer: composer,
          queuedEdit: queuedEdit,
        ),
      if (view.planSteps case final AgentChatItem steps when view.busy)
        AgentChatPlanProgressDock(item: steps),
      if (view.archived)
        AleraInlineNotice(
          message:
              'This chat is archived. Its history stays on the runtime; '
              'reopen it from $agentChatArchivedChatsLabel to continue.',
          child: onOpenArchived == null
              ? null
              : Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    key: const ValueKey<String>('agent-chat-open-archived'),
                    onPressed: onOpenArchived,
                    child: const Text(agentChatArchivedChatsLabel),
                  ),
                ),
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
            AgentChatShortcutTarget(
              chatId: chatId,
              workspaceId: workspace.id,
              queuedEdit: queuedEdit,
            ),
            // Hides itself on runtimes without chat tasks or with none open,
            // so it sits outside the spaced docks.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
              ),
              child: ChatTasksForChat(
                chatId: chatId,
                parentHasPendingRequest: view.requests.isNotEmpty,
              ),
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
                settings: settings,
                usage: view.usage,
                canSend: view.canSend,
                canSubmit: canSubmit,
                canSteer: view.canSteer,
                busy: view.busy,
                canInterrupt: view.canInterrupt,
                interrupting: view.interrupting,
                hintText: view.nativeOperation != null
                    ? agentChatNativeOperationSendBlockedHint
                    : _hint(
                        view.live,
                        view.busy,
                        view.requests,
                        settings,
                        approvalSend,
                        refiningPlan: view.refiningPlan,
                      ),
                sendLabel: approvalSend?.sendLabel,
                promptHistory: () =>
                    ref.read(provider).projection?.promptHistory ??
                    const <String>[],
                pickerController: pickerController,
                queuedEdit: queuedEdit,
                onSaveQueuedEdit: controller.editQueued,
                onSend: (text, attachments, {steer = false}) {
                  final delivery = steer
                      ? AgentChatDelivery.steer
                      : AgentChatDelivery.auto;
                  if (approvalSend == null) {
                    return controller.send(
                      text,
                      attachments: attachments,
                      delivery: delivery,
                    );
                  }
                  _sendOverApprovals(
                    controller,
                    approvalSend,
                    composer,
                    text,
                    attachments,
                    delivery,
                  );
                  return false;
                },
                onInterrupt: () => unawaited(controller.interrupt()),
                onConfigure: (configuration) =>
                    unawaited(controller.configure(configuration)),
                onChoose: (pick, label) =>
                    unawaited(controller.choose(pick, label: label)),
                onRetryCatalog: () => ref.invalidate(catalogProvider),
                onOpenProviderSettings: openProviderSettings,
                chatActions: AgentChatActionsMenu(
                  chatId: chatId,
                  workspaceId: workspace.id,
                ),
                onOpenFile: onOpenFile,
                skills: skills,
                fileSearch: WorkspaceAgentChatComposerFileSearch(
                  workspace: workspace,
                  files: ref.read(workspaceFileServiceProvider),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The composer keeps its draft until the approvals are answered and the
/// message is taken, and clears only if the draft is still what was sent.
void _sendOverApprovals(
  AgentChatController controller,
  AgentChatApprovalSend plan,
  TerminalComposerController composer,
  String text,
  List<AgentChatAttachment> attachments,
  AgentChatDelivery delivery,
) {
  final sentText = composer.textController.text;
  List<String> attachmentIds() => <String>[
    for (final attachment in composer.attachments) attachment.id,
  ];
  final sentAttachments = attachmentIds();
  bool draftChanged() =>
      composer.textController.text != sentText ||
      !listEquals(attachmentIds(), sentAttachments);
  unawaited(
    controller
        .sendOverApprovals(
          plan,
          text,
          attachments: attachments,
          delivery: delivery,
          draftChanged: draftChanged,
        )
        .then((outcome) {
          if (outcome.notice case final String notice) {
            AleraToast.publish(message: notice);
          }
          if (!outcome.sent || draftChanged()) return;
          composer.textController.clear();
          composer.removeAttachments(sentAttachments);
        }),
  );
}

String _hint(
  bool live,
  bool busy,
  List<AgentChatRequest> requests,
  AgentChatComposerSettings settings,
  AgentChatApprovalSend? approvalSend, {
  required bool refiningPlan,
}) {
  if (!live) return 'Reconnecting to the Alera runtime';
  if (approvalSend != null) return approvalSend.hint;
  if (requests.isNotEmpty) return agentChatRequestPendingHint;
  if (!settings.hasSelection) return 'Choose an agent to start this chat';
  if (settings.catalog == AgentChatCatalogState.ready &&
      settings.providerUnavailable) {
    return '${settings.providerLabel} cannot start yet; your draft is kept';
  }
  if (busy) return 'Send a message to queue it after this turn';
  if (refiningPlan) return 'Describe what to change in the plan';
  return 'Ask ${settings.providerLabel} anything';
}
