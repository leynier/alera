import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_view_memory.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_availability.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_footer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_history_actions.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_native_history_banner.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_plan_dock.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_provider_identity.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_ready_state.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_request_dock.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_shimmer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_status_banner.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_timeline_view.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the chat body asks of the tab that owns the composer state.
abstract interface class AgentChatTabHandlers {
  AgentChatTypingClock get typing;
  Listenable get scrollToEnd;
  Future<void> send({bool steer = false});
  Future<void> run(String what, Future<void> Function() action);
  Future<void> editQueued(AgentChatQueueEntry entry);
  Future<void> editQueuedInPlace(AgentChatQueueEntry entry);
  Future<void> reopen();
  void openProviderSettings();
  VoidCallback? attachHandler(AgentChatViewState view);
  void removeAttachment(AgentChatDraftAttachment attachment);
  void startNewChatWithText();
  Future<void> fork(String turnId);
  Future<void> rewind(String turnId, AgentChatRewindOptions options);
  Future<void> reconcile(
    AgentChatNativeOperation operation,
    AgentChatNativeHistoryAction action,
  );
  bool get reconciling;
  Future<void> viewChanges(String turnId);
  Future<void> implementPlan(AgentChatItem plan);
}

/// The laid-out chat: transcript, then notices, the request dock, tasks and
/// queue, then the composer with its agent and model chip.
class const AgentChatTabBody({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final String chatId,
  required final String provider,
  required final String? remoteHostId,
  required final AgentChatViewState view,
  required final AgentChatAvailability availability,
  required final bool animate,
  required final AgentChatViewMemory memory,
  required final TextEditingController composer,
  required final FocusNode focusNode,
  required final List<AgentChatDraftAttachment> attachments,
  required final String draftText,
  required final AgentChatTabHandlers handlers,
  required final AgentChatController controller,
  required final VoidCallback onRetryConnection,
  required final bool canStartNewChat,
  required final double minimumComposerHeight,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (view.removed) {
      return AgentChatRemovedState(
        draftText: draftText,
        onStartNewChat: canStartNewChat ? handlers.startNewChatWithText : null,
      );
    }
    final canAct = availability.allowsInput;
    final providers = ref
        .watch(agentChatProvidersProvider(hostId, workspaceId))
        .value;
    final instance = agentChatInstanceOf(providers, view);
    final agentLabel =
        instance?.label ??
        agentChatProviderName(
          view.thread.provider.isEmpty ? provider : view.thread.provider,
        );
    final requests = view.timeline.requests;
    final problem = _providerProblem(instance, agentLabel);
    final queueSteer =
        ref
            .watch(
              agentChatCapabilityProvider(
                hostId,
                AgentChatWire.queueSteerCapability,
              ),
            )
            .value ??
        false;
    final steerable = view.session.capabilities.steer && view.turnActive;
    bool runtimeOffers(String capability) =>
        ref.watch(agentChatCapabilityProvider(hostId, capability)).value ??
        false;
    final native = view.session.capabilities;
    final canFork =
        canAct && native.fork && runtimeOffers(AgentChatWire.forkCapability);
    // The shared rules decide which rewinds exist right now; none while the
    // chat is busy or a history change is still pending.
    final rewind = AgentChatRewindOptions.resolve(
      session: view.session,
      transcriptSupported: runtimeOffers(AgentChatWire.rewindCapability),
      conversationSupported: runtimeOffers(
        AgentChatWire.nativeRewindCapability,
      ),
      filesSupported: runtimeOffers(AgentChatWire.rewindFilesCapability),
      pendingOperation: view.thread.pendingNativeOperation,
    );
    final canRewind = canAct && rewind.any;
    final operation = view.thread.pendingNativeOperation;
    final canViewChanges = runtimeOffers(AgentChatWire.turnDiffCapability);
    final editsInPlace = runtimeOffers(AgentChatWire.queueEditCapability);
    final tasksSupported =
        ref.watch(mobileChatTasksSupportedProvider(hostId)).value ?? false;
    final canDelegate = canAct && tasksSupported;
    // The tasks dock draws nothing without tasks, so it is only mounted when
    // there are some: a mounted dock reserves footer room the composer needs.
    final hasTasks =
        tasksSupported &&
        (ref
                .watch(
                  mobileChatTaskListProvider(
                    hostId,
                    AgentChatTaskQuery(parentChatId: chatId),
                  ),
                )
                .value
                ?.tasks
                .isNotEmpty ??
            false);
    final plan = agentChatRunningPlan(view.timeline);
    final recovery = view.thread.recovery;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: <Widget>[
          Expanded(
            child: AgentChatShimmerScope(
              enabled: animate && !MediaQuery.disableAnimationsOf(context),
              child: AgentChatScope(
                hostId: hostId,
                workspaceId: workspaceId,
                chatId: chatId,
                cwd: view.session.cwd,
                memory: memory,
                child: AgentChatHistoryActions(
                  onFork: canFork
                      ? (turnId) => unawaited(handlers.fork(turnId))
                      : null,
                  onRewind: canRewind
                      ? (turnId) => unawaited(handlers.rewind(turnId, rewind))
                      : null,
                  onViewChanges: canViewChanges
                      ? (turnId) => unawaited(handlers.viewChanges(turnId))
                      : null,
                  onImplementPlan: canDelegate
                      ? (item) => unawaited(handlers.implementPlan(item))
                      : null,
                  child: AgentChatTimelineView(
                    timeline: view.timeline,
                    memory: memory,
                    scrollToEnd: handlers.scrollToEnd,
                    emptyState: view.neverSent
                        ? AgentChatReadyState(
                            agentType: view.unselected
                                ? null
                                : agentChatAgentType(
                                    instance?.provider ?? view.thread.provider,
                                  ),
                            agentLabel: view.unselected
                                ? agentChatNoAgentLabel
                                : agentLabel,
                            modelLabel: view.unselected
                                ? null
                                : _modelLabel(instance),
                            workspacePath: view.session.cwd,
                          )
                        : AleraEmptyState(
                            icon: AleraIcons.agent,
                            message:
                                'Ask $agentLabel to work on this workspace.',
                          ),
                    canLoadEarlier: view.thread.historyBefore != null,
                    loadingEarlier: view.loadingHistory,
                    canRespond: canAct,
                    onLoadEarlier: () => unawaited(
                      handlers.run(
                        'Could not load earlier messages.',
                        controller.loadEarlier,
                      ),
                    ),
                    onRetry: (id) => unawaited(
                      handlers.run(
                        'Could not send the message.',
                        () => controller.retry(id),
                      ),
                    ),
                    onEdit: controller.edit,
                  ),
                ),
              ),
            ),
          ),
          _TransitionAnnouncer(view: view),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight),
            child: AgentChatFooter(
              minimumComposerHeight: minimumComposerHeight,
              notices: <Widget>[
                if (operation != null)
                  AgentChatNativeOperationBanner(
                    key: ValueKey<String>('native-${operation.operationId}'),
                    operation: operation,
                    enabled: canAct,
                    busy: handlers.reconciling,
                    onAction: (action) =>
                        unawaited(handlers.reconcile(operation, action)),
                  ),
                if (recovery != null && !view.thread.archived)
                  AgentChatRecoveryBanner(
                    recovery: recovery,
                    enabled: canAct,
                    onOpenProviderSettings: handlers.openProviderSettings,
                    onRecover: (mode) => unawaited(
                      handlers.run(
                        'Could not restart the agent.',
                        () => controller.recover(mode),
                      ),
                    ),
                  ),
                if (availability != AgentChatAvailability.live)
                  AgentChatStatusBanner(
                    availability: availability,
                    onRetry: onRetryConnection,
                    onReopen: () => unawaited(handlers.reopen()),
                  ),
                if (problem != null && !view.thread.archived)
                  AgentChatProviderNotice(
                    message: problem,
                    onOpenProviderSettings: handlers.openProviderSettings,
                  ),
                if (plan != null) AgentChatPlanDock(plan: plan),
              ],
              requests: requests,
              queue: view.thread.queue,
              canRespond: canAct,
              respondingRequestIds: view.respondingRequestIds,
              typing: handlers.typing,
              onRespond: (request, response) => handlers.run(
                'Could not answer the agent.',
                () => controller.respond(request, response),
              ),
              onRemoveQueued: (entry) => handlers.run(
                'Could not remove the queued message.',
                () => controller.cancelQueued(entry),
              ),
              // In place where the runtime rewrites an entry atomically;
              // elsewhere the entry returns to the composer.
              onEditQueued: editsInPlace
                  ? handlers.editQueuedInPlace
                  : handlers.editQueued,
              onSteerQueued: queueSteer && steerable && canAct
                  ? (entry) => handlers.run(
                      'Could not steer the queued message.',
                      () => controller.steerQueued(entry),
                    )
                  : null,
              tasks: hasTasks
                  ? ChatTasksForChat(
                      chatId: chatId,
                      hostId: hostId,
                      parentHasPendingRequest: requests.isNotEmpty,
                    )
                  : null,
              composer: AgentChatComposer(
                hostId: hostId,
                workspaceId: workspaceId,
                chatId: chatId,
                controller: composer,
                focusNode: focusNode,
                attachments: attachments,
                enabled: canAct,
                // A pending history change keeps the draft here until the
                // operation finishes or is reconciled.
                sendBlocked: problem != null || view.nativeOperationPending,
                hintText: switch (availability) {
                  AgentChatAvailability.readOnly => 'This chat is archived',
                  AgentChatAvailability.live when view.nativeOperationPending =>
                    agentChatNativeOperationSendBlockedHint,
                  AgentChatAvailability.live
                      when requests.any((request) => request.isApproval) =>
                    agentChatWaitingForDecisionHint,
                  AgentChatAvailability.live => 'Ask $agentLabel anything',
                  _ => 'Waiting for the host',
                },
                turnActive: view.turnActive,
                canInterrupt: view.session.capabilities.interrupt,
                interrupting: view.interrupting,
                onAttach: handlers.attachHandler(view),
                onRemoveAttachment: handlers.removeAttachment,
                onSend: () => unawaited(handlers.send()),
                onSteer: steerable
                    ? () => unawaited(handlers.send(steer: true))
                    : null,
                onStop: () => unawaited(
                  handlers.run(
                    'Could not stop the agent.',
                    controller.interrupt,
                  ),
                ),
                settings: AgentChatComposerControls(
                  hostId: hostId,
                  workspaceId: workspaceId,
                  remoteHostId: remoteHostId,
                  view: view,
                  enabled: canAct,
                  onOpenProviderSettings: handlers.openProviderSettings,
                  onSelect: (selection) => handlers.run(
                    'Could not change the agent.',
                    () => controller.select(selection),
                  ),
                  onConfigure: (configuration) => handlers.run(
                    'Could not change the chat settings.',
                    () => controller.configure(configuration),
                  ),
                  onFileCheckpointing: (enabled) => handlers.run(
                    'Could not change file checkpointing.',
                    () => controller.configureFileCheckpoints(enabled: enabled),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Why Send waits: no agent yet, or one the host cannot run right now.
  String? _providerProblem(
    AgentChatProviderInstance? instance,
    String agentLabel,
  ) {
    if (view.unselected) {
      return 'This chat has no agent yet. Pick one from the chip below.';
    }
    if (instance == null) return null;
    if (!instance.enabled) return '$agentLabel is turned off on this host.';
    if (!instance.available) {
      return instance.unavailableReason ??
          '$agentLabel is not available on this host.';
    }
    return null;
  }

  String _modelLabel(AgentChatProviderInstance? instance) {
    final model = view.selection?.model;
    if (model == null) return agentChatProviderDefaultLabel;
    return instance?.modelById(model)?.label ?? model;
  }
}

/// Says the moments that matter out loud for a screen reader, once each: a
/// request needing an answer, a turn finishing, a turn failing.
class const _TransitionAnnouncer({required final AgentChatViewState view})
    extends StatefulWidget {
  @override
  State<_TransitionAnnouncer> createState() => _TransitionAnnouncerState();
}

class _TransitionAnnouncerState extends State<_TransitionAnnouncer> {
  String _label = '';

  @override
  void didUpdateWidget(covariant _TransitionAnnouncer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.view;
    final after = widget.view;
    final next =
        after.timeline.requests.length > before.timeline.requests.length
        ? 'The agent needs your response.'
        : before.turnActive && !after.turnActive
        ? (_lastTurnFailed(after) ? 'The turn failed.' : 'The turn finished.')
        : null;
    if (next != null) _label = next;
  }

  bool _lastTurnFailed(AgentChatViewState view) =>
      switch (view.thread.turns.lastOrNull?.status) {
        AgentChatTurnStatus.failed => true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: _label,
    child: const SizedBox.shrink(),
  );
}
