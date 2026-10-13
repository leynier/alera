import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_availability.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_attachment_picker.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_footer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_mode_labels.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_provider_identity.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_settings_sheet.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_shimmer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_status_banner.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_timeline_view.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_usage_button.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

/// The body of an agent chat tab. Everything shown comes from the runtime's
/// copy of the chat; a dropped connection keeps the last copy readable and
/// the composed text in its draft, and nothing here navigates on its own.
class const AgentChatTabView({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final String chatId,
  required final String provider,
  final bool remoteWorkspace = false,
  final ValueChanged<String>? onOpenTab,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatTabView> createState() => _AgentChatTabViewState();
}

class _AgentChatTabViewState extends ConsumerState<AgentChatTabView> {
  static final Logger _logger = Logger('AgentChatTabView');
  late final AgentChatDraftStore _store;
  late final TextEditingController _composer;
  final FocusNode _focus = FocusNode();
  List<AgentChatDraftAttachment> _attachments =
      const <AgentChatDraftAttachment>[];
  bool _restoring = false;

  AgentChatControllerProvider get _provider => agentChatControllerProvider(
    widget.hostId,
    widget.workspaceId,
    widget.chatId,
  );

  @override
  void initState() {
    super.initState();
    _store = ref.read(agentChatDraftStoreProvider)
      ..activate(widget.hostId, widget.chatId);
    final draft = _store.read(widget.hostId, widget.chatId);
    _composer = TextEditingController.fromValue(draft.value)
      ..addListener(_persist);
    _attachments = draft.attachments;
    _store.addListener(widget.hostId, widget.chatId, _restored);
  }

  @override
  void dispose() {
    _store.removeListener(widget.hostId, widget.chatId, _restored);
    _composer
      ..removeListener(_persist)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  void _persist() {
    if (_restoring) return;
    _store.write(
      widget.hostId,
      widget.chatId,
      AgentChatComposerDraft(value: _composer.value, attachments: _attachments),
    );
  }

  /// An upload finished or a refused prompt came back while this was shown.
  void _restored() {
    if (!mounted) return;
    final draft = _store.read(widget.hostId, widget.chatId);
    _restoring = true;
    _composer.value = draft.value;
    _restoring = false;
    setState(() => _attachments = draft.attachments);
  }

  void _removeAttachment(AgentChatDraftAttachment attachment) {
    setState(() {
      _attachments = <AgentChatDraftAttachment>[
        for (final existing in _attachments)
          if (existing != attachment) existing,
      ];
    });
    _persist();
  }

  Future<void> _send() async {
    final draft = AgentChatComposerDraft(
      value: _composer.value,
      attachments: _attachments,
    );
    if (!draft.canSubmit) return;
    _restoring = true;
    _composer.clear();
    _restoring = false;
    setState(() => _attachments = const <AgentChatDraftAttachment>[]);
    _store.write(widget.hostId, widget.chatId, const AgentChatComposerDraft());
    try {
      await ref.read(_provider.notifier).send(draft);
    } on Object catch (error, stackTrace) {
      _store.restore(widget.hostId, widget.chatId, draft);
      _report('Could not send the message.', error, stackTrace);
    }
  }

  /// Runs an action and explains a failure, without leaving the chat.
  Future<void> _run(String what, Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error, stackTrace) {
      _report(what, error, stackTrace);
    }
  }

  void _report(String what, Object error, StackTrace stackTrace) {
    _logger.warning(what, error, stackTrace);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(agentChatErrorMessage(error))));
  }

  Future<void> _editQueued(AgentChatQueueEntry entry) => _run(
    'Could not edit the queued message.',
    () async {
      final withdrawn = await ref.read(_provider.notifier).cancelQueued(entry);
      if (!withdrawn) return;
      _store.restore(
        widget.hostId,
        widget.chatId,
        AgentChatComposerDraft.fromMessage(entry.text, entry.attachments),
      );
    },
  );

  Future<void> _reopen() => _run('Could not reopen the chat.', () async {
    final repository = await ref.read(
      agentChatRepositoryProvider(widget.hostId).future,
    );
    final result = await repository.reopen(
      AgentChatRef(chatId: widget.chatId, workspaceId: widget.workspaceId),
      requestId: const Uuid().v4(),
    );
    final tabId = result.tabId;
    if (tabId != null) widget.onOpenTab?.call(tabId);
  });

  Future<void> _openSettings(AgentChatViewState view) =>
      _run('Could not load the agent settings.', () async {
        final providers = await ref.read(
          agentChatProvidersProvider(widget.hostId, widget.workspaceId).future,
        );
        if (!mounted) return;
        await showAgentChatSettingsSheet(
          context,
          providers: providers,
          current: AgentChatSettingsCurrent(
            providerInstanceId: view.thread.providerInstanceId,
            model: view.session.model,
            runtimeMode: view.session.runtimeMode,
            interactionMode: view.session.interactionMode,
            canSwitchProvider:
                !view.turnActive &&
                view.thread.pendingRequests.isEmpty &&
                view.thread.queue.isEmpty,
          ),
          onConfigure: (configuration) => _run(
            'Could not change the agent settings.',
            () => ref.read(_provider.notifier).configure(configuration),
          ),
        );
      });

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_provider);
    final view = async.value;
    if (view == null) {
      return switch (async) {
        AsyncError(:final error) => AleraEmptyState(
          icon: AleraIcons.loadFailed,
          title: error is AgentChatUpdateRequired
              ? 'Update required'
              : 'Could not open this chat',
          message: agentChatErrorMessage(error),
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(_provider),
            icon: const Icon(AleraIcons.refresh),
            label: const Text('Retry'),
          ),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }
    final availability = agentChatAvailability(
      refreshing: async.isLoading,
      failed: async.hasError,
      disconnected: view.stale,
      readOnly: view.thread.archived,
    );
    final canAct = availability.allowsInput;
    final controller = ref.read(_provider.notifier);
    final lifecycle = ref.watch(appLifecycleControllerProvider);
    final providerName = agentChatProviderName(
      view.thread.provider.isEmpty ? widget.provider : view.thread.provider,
    );
    final recovery = view.thread.recovery;
    final tasksSupported =
        ref.watch(mobileChatTasksSupportedProvider(widget.hostId)).value ==
        true;
    final taskPage = tasksSupported
        ? ref
              .watch(
                mobileChatTaskListProvider(
                  widget.hostId,
                  AgentChatTaskQuery(parentChatId: widget.chatId),
                ),
              )
              .value
        : null;
    final hasTasks =
        taskPage?.tasks.any(
          (task) => !task.status.settled || task.needsAttention,
        ) ==
        true;
    return Column(
      children: <Widget>[
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: <Widget>[
                Expanded(
                  child: AgentChatShimmerScope(
                    enabled:
                        view.turnActive &&
                        lifecycle == AppLifecycleState.resumed &&
                        TickerMode.valuesOf(context).enabled &&
                        !MediaQuery.disableAnimationsOf(context),
                    child: AgentChatScope(
                      hostId: widget.hostId,
                      workspaceId: widget.workspaceId,
                      chatId: widget.chatId,
                      cwd: view.session.cwd,
                      child: AgentChatTimelineView(
                        timeline: view.timeline,
                        emptyMessage:
                            'Ask $providerName to work on this workspace.',
                        canLoadEarlier: view.thread.historyBefore != null,
                        loadingEarlier: view.loadingHistory,
                        canRespond: canAct,
                        respondingRequestIds: view.respondingRequestIds,
                        onLoadEarlier: () => unawaited(
                          _run(
                            'Could not load earlier messages.',
                            controller.loadEarlier,
                          ),
                        ),
                        onRespond: (request, response) => _run(
                          'Could not answer the agent.',
                          () => controller.respond(request, response),
                        ),
                        onRetry: (id) => unawaited(
                          _run(
                            'Could not send the message.',
                            () => controller.retry(id),
                          ),
                        ),
                        onEdit: controller.edit,
                      ),
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: constraints.maxHeight),
                  child: AgentChatFooter(
                    minimumComposerHeight: agentChatComposerMinimumHeight(
                      context,
                    ),
                    notices: <Widget>[
                      if (availability != AgentChatAvailability.live)
                        AgentChatStatusBanner(
                          availability: availability,
                          onRetry: () => ref.invalidate(_provider),
                          onReopen: () => unawaited(_reopen()),
                        ),
                      if (recovery != null && !view.thread.archived)
                        AgentChatRecoveryBanner(
                          recovery: recovery,
                          enabled: canAct,
                          onRecover: (mode) => unawaited(
                            _run(
                              'Could not restart the agent.',
                              () => controller.recover(mode),
                            ),
                          ),
                        ),
                    ],
                    questions: view.timeline.questions,
                    queue: view.thread.queue,
                    canRespond: canAct,
                    respondingRequestIds: view.respondingRequestIds,
                    onRespond: (request, response) => _run(
                      'Could not answer the agent.',
                      () => controller.respond(request, response),
                    ),
                    onRemoveQueued: (entry) => _run(
                      'Could not remove the queued message.',
                      () => controller.cancelQueued(entry),
                    ),
                    onEditQueued: _editQueued,
                    tasks: hasTasks
                        ? ChatTasksForChat(
                            chatId: widget.chatId,
                            hostId: widget.hostId,
                          )
                        : null,
                    composer: AgentChatComposer(
                      hostId: widget.hostId,
                      workspaceId: widget.workspaceId,
                      chatId: widget.chatId,
                      controller: _composer,
                      focusNode: _focus,
                      attachments: _attachments,
                      enabled: canAct,
                      hintText: switch (availability) {
                        AgentChatAvailability.readOnly =>
                          'This chat is archived',
                        AgentChatAvailability.live =>
                          'Ask $providerName anything',
                        _ => 'Waiting for the host',
                      },
                      turnActive: view.turnActive,
                      canInterrupt: view.session.capabilities.interrupt,
                      interrupting: view.interrupting,
                      onAttach: _attachHandler(view),
                      onRemoveAttachment: _removeAttachment,
                      onSend: () => unawaited(_send()),
                      onStop: () => unawaited(
                        _run('Could not stop the agent.', controller.interrupt),
                      ),
                      settings: Row(
                        mainAxisSize: .min,
                        children: <Widget>[
                          Flexible(
                            child: TextButton.icon(
                              onPressed: canAct
                                  ? () => unawaited(_openSettings(view))
                                  : null,
                              icon: const Icon(AleraIcons.tune),
                              label: Text(
                                agentChatSettingsSummary(
                                  providerLabel: providerName,
                                  model: view.session.model,
                                  interactionMode: view.session.interactionMode,
                                ),
                                overflow: .ellipsis,
                              ),
                            ),
                          ),
                          AgentChatUsageButton(usage: view.thread.usage),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Attachments are offered when the provider takes them and the runtime
  /// serves at least one source for this workspace.
  VoidCallback? _attachHandler(AgentChatViewState view) {
    final capabilities = view.session.capabilities;
    if (!capabilities.attachments && !capabilities.images) return null;
    final sources = AgentChatAttachmentSources.read(
      ref,
      widget.hostId,
      remoteWorkspace: widget.remoteWorkspace,
    );
    if (sources.isEmpty) return null;
    return () => unawaited(
      pickAgentChatAttachments(
        context,
        ref,
        hostId: widget.hostId,
        workspaceId: widget.workspaceId,
        chatId: widget.chatId,
        sources: sources,
      ),
    );
  }
}
