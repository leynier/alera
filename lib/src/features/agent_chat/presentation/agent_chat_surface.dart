import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_commands.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_direct_open.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_archived_chats_dialog.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_settings.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_find_bar.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_footer.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_full_data.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_plan_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_status_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface_history.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_view.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_workspace_file_opener.dart';
import 'package:alera/src/features/workbench/presentation/workbench_pane_focus_registry.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One chat in a workbench tab: the conversation above, the docks and the
/// composer below. The runtime owns the chat; this view only renders it and
/// forwards the person's actions.
class const AgentChatSurface({
  super.key,
  required final String chatId,
  required final Workspace workspace,
  required final String fallbackTitle,
  required final String fallbackProvider,
  final bool autofocus = false,
  final ExternalUriLauncher? uriLauncher,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatSurface> createState() => _AgentChatSurfaceState();
}

class _AgentChatSurfaceState extends ConsumerState<AgentChatSurface>
    with WidgetsBindingObserver {
  final TerminalComposerController _composer = TerminalComposerController();
  final AleraPopoverController _picker = AleraPopoverController();
  late final AgentChatComposerDrafts _drafts;
  late AgentChatTimelineActions _actions;
  bool _restoringDraft = false;
  AgentChatTurnHistoryActions get _history => AgentChatTurnHistoryActions(
    chat: AgentChatRef(chatId: widget.chatId, workspaceId: widget.workspace.id),
    composer: _composer,
    onOpenFile: (path) => unawaited(_openFile(path)),
  );
  AgentChatHistorySupport _historySupport = (
    fork: false,
    diff: false,
    rewind: const AgentChatRewindOptions(),
  );

  AgentChatControllerProvider get _provider =>
      agentChatControllerProvider(widget.chatId, widget.workspace.id);

  @override
  void initState() {
    super.initState();
    _drafts = ref.read(agentChatComposerDraftsProvider);
    WidgetsBinding.instance.addObserver(this);
    _listenToDraft();
    _restoreDraft();
    // The draft map stays current while typing, so New Agent Chat can tell
    // an empty never-sent chat from one with unsent text.
    _composer.addListener(_saveCurrentDraft);
    _composer.textController.addListener(_saveCurrentDraft);
    _actions = _buildActions(implementablePlanId: null);
    // New Agent Chat focuses the chat it created even in a surface that
    // does not autofocus, such as the side panel's single surface; a chat
    // created while the person moved on to another field waits for that
    // field to let go.
    final requested = ref
        .read(agentChatDirectOpenerProvider)
        .takeInitialFocus(widget.chatId);
    if (requested != null || widget.autofocus) {
      _focusComposerNextFrame(onlyIfParked: requested ?? false);
    }
  }

  void _saveCurrentDraft() {
    if (!_restoringDraft) _saveDraft(widget.chatId, widget.workspace);
  }

  void _listenToDraft() {
    _drafts.addListener(
      widget.chatId,
      _restoreDraft,
      hostId: widget.workspace.hostId,
      workspaceId: widget.workspace.id,
    );
    unawaited(
      _drafts.hydrate(
        widget.chatId,
        hostId: widget.workspace.hostId,
        workspaceId: widget.workspace.id,
      ),
    );
  }

  void _stopListeningToDraft(String chatId, Workspace workspace) =>
      _drafts.removeListener(
        chatId,
        _restoreDraft,
        hostId: workspace.hostId,
        workspaceId: workspace.id,
      );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_drafts.flush());
  }

  /// Another client discarded or deleted this chat. Unsent text here is the
  /// person's and must survive; it can start a new chat, never by itself.
  void _offerRemovedDraft() {
    final draft = AgentChatComposerDraft(
      text: _composer.textController.text,
      attachments: List.unmodifiable(_composer.attachments),
    );
    if (draft.isEmpty) return;
    // The tab may close before the toast's action is pressed.
    final container = ProviderScope.containerOf(context, listen: false);
    final workspace = widget.workspace;
    final chatId = widget.chatId;
    AleraToast.publish(
      message:
          'This chat was removed on another device. Your unsent text is '
          'kept.',
      actionLabel: 'Start New Chat With This Text',
      onAction: () {
        container
            .read(agentChatComposerDraftsProvider)
            .remove(
              chatId,
              hostId: workspace.hostId,
              workspaceId: workspace.id,
            );
        unawaited(
          container
              .read(agentChatDirectOpenerProvider)
              .open(
                read: container.read,
                exists: container.exists,
                workspace: workspace,
                draft: draft,
              ),
        );
      },
    );
  }

  void _onCommand(AgentChatComposerCommand? command) {
    if (command == null || command.chatId != widget.chatId || !mounted) {
      return;
    }
    switch (command.kind) {
      case AgentChatComposerCommandKind.focus:
        _composer.focusNode.requestFocus();
      case AgentChatComposerCommandKind.chooseModel:
        _picker.open();
    }
  }

  @override
  void didUpdateWidget(covariant AgentChatSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId ||
        oldWidget.workspace.id != widget.workspace.id ||
        oldWidget.workspace.hostId != widget.workspace.hostId) {
      _stopListeningToDraft(oldWidget.chatId, oldWidget.workspace);
      _saveDraft(oldWidget.chatId, oldWidget.workspace);
      _listenToDraft();
      _restoreDraft();
    }
    if (!oldWidget.autofocus && widget.autofocus) {
      // The pane became active while this chat was showing; take the
      // keyboard only when nothing else is being typed in.
      _focusComposerNextFrame(onlyIfParked: true);
    }
  }

  @override
  void dispose() {
    _saveDraft(widget.chatId, widget.workspace);
    _stopListeningToDraft(widget.chatId, widget.workspace);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_drafts.flush());
    _composer.removeListener(_saveCurrentDraft);
    _composer.textController.removeListener(_saveCurrentDraft);
    _composer.dispose();
    _picker.dispose();
    super.dispose();
  }

  void _restoreDraft() {
    if (!mounted) return;
    final draft = _drafts.read(
      widget.chatId,
      hostId: widget.workspace.hostId,
      workspaceId: widget.workspace.id,
    );
    _restoringDraft = true;
    _composer.textController.text = draft.text;
    _composer.removeAttachments(
      _composer.attachments.map((attachment) => attachment.id).toList(),
    );
    for (final attachment in draft.attachments) {
      _composer.addAttachment(
        kind: attachment.kind,
        path: attachment.path,
        displayName: attachment.displayName,
        localSourcePath: attachment.localSourcePath,
        attachmentId: attachment.attachmentId,
        sizeBytes: attachment.sizeBytes,
      );
    }
    _restoringDraft = false;
  }

  void _saveDraft(String chatId, Workspace workspace) => _drafts.write(
    chatId,
    AgentChatComposerDraft(
      text: _composer.textController.text,
      attachments: List.unmodifiable(_composer.attachments),
    ),
    hostId: workspace.hostId,
    workspaceId: workspace.id,
  );

  void _focusComposerNextFrame({required bool onlyIfParked}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (!onlyIfParked || workbenchFocusIsParked())) {
        _composer.focusNode.requestFocus();
      }
    });
  }

  AgentChatController get _controller => ref.read(_provider.notifier);

  AgentChatTimelineActions _buildActions({
    required String? implementablePlanId,
  }) => AgentChatTimelineActions(
    chatId: widget.chatId,
    onRetrySend: (id) => unawaited(_controller.retrySend(id)),
    onEditSend: _editFailedSend,
    onOpenLink: (link) => unawaited(_openLink(link)),
    onOpenFile: (path) => unawaited(_openFile(path)),
    onImplementPlan: () => unawaited(_implementPlan()),
    implementablePlanId: implementablePlanId,
    onRefinePlan: _composer.focusNode.requestFocus,
    onForkTurn: _historySupport.fork
        ? (turnId) => unawaited(_history.fork(context, ref, turnId))
        : null,
    onRewindTurn: _historySupport.rewind.transcript
        ? (turnId) => unawaited(_history.rewind(context, ref, turnId))
        : null,
    onNativeRewindTurn: _historySupport.rewind.conversation
        ? (turnId) => unawaited(
            _history.rewind(
              context,
              ref,
              turnId,
              kind: AgentChatRewindKind.conversation,
            ),
          )
        : null,
    onRewindFilesTurn: _historySupport.rewind.files
        ? (turnId) => unawaited(_history.rewindFiles(context, ref, turnId))
        : null,
    onShowTurnDiff: _historySupport.diff
        ? (turnId) => unawaited(_history.showDiff(context, ref, turnId))
        : null,
  );

  void _editFailedSend(String clientMessageId) {
    final message = _controller.discardSend(clientMessageId);
    if (message == null) return;
    if (appendAgentChatDraft(_composer, message.text, message.attachments)) {
      AleraToast.publish(
        message: 'The failed message was added to your draft.',
      );
    }
  }

  Future<void> _implementPlan() async {
    final accepted = await _controller.configure(
      const AgentChatConfiguration(
        interactionMode: AgentChatInteractionMode.standard,
      ),
    );
    if (accepted && mounted) _controller.send('Implement the plan.');
  }

  Future<void> _openFile(String path) async {
    try {
      if (await openTerminalComposerWorkspaceFile(
        ref,
        widget.workspace.id,
        path,
        sourceKey: 'chat:${widget.chatId}',
      )) {
        return;
      }
      await (widget.uriLauncher ?? UrlLauncherExternalUriLauncher()).open(
        Uri.file(path),
      );
    } on Object catch (error) {
      AleraToast.publish(message: 'Could not open $path: $error', tone: .error);
    }
  }

  /// Agent output is untrusted: only web and mail links leave the app, and a
  /// bare path opens as a workspace file.
  Future<void> _openLink(String link) async {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return;
    if (!uri.hasScheme) return _openFile(uri.path);
    if (!const <String>{'http', 'https', 'mailto'}.contains(uri.scheme)) {
      AleraToast.publish(message: 'This link cannot be opened from a chat.');
      return;
    }
    try {
      await (widget.uriLauncher ?? UrlLauncherExternalUriLauncher()).open(uri);
    } on Object catch (error) {
      AleraToast.publish(
        message: 'Could not open the link: $error',
        tone: .error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(agentChatComposerCommandsProvider, (_, command) {
      _onCommand(command);
    });
    ref.listen(_provider.select((state) => state.removed), (was, removed) {
      if (removed && was != true) _offerRemovedDraft();
    });
    final phase = ref.watch(_provider.select((state) => state.phase));
    final hasThread = ref.watch(
      _provider.select((state) => state.thread != null),
    );
    if (!hasThread) {
      return switch (phase) {
        AgentChatPhase.unsupported => const AgentChatUpdateRequiredView(),
        AgentChatPhase.failed => AgentChatFailedView(
          message:
              ref.read(_provider).loadError ?? 'The chat could not be read.',
          onRetry: () => unawaited(_controller.retry()),
        ),
        _ => const AgentChatLoadingView(),
      };
    }
    return ColoredBox(
      color: AleraTokens.bg,
      child: LayoutBuilder(
        builder: (context, constraints) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: AgentChatFindHost(
                chat: AgentChatRef(
                  chatId: widget.chatId,
                  workspaceId: widget.workspace.id,
                ),
                child: _buildTimeline(),
              ),
            ),
            AgentChatFooter(
              chatId: widget.chatId,
              workspace: widget.workspace,
              fallbackProvider: widget.fallbackProvider,
              composer: _composer,
              pickerController: _picker,
              requestDockMaxHeight: constraints.maxHeight.isFinite
                  ? constraints.maxHeight *
                        AleraTokens.agentChatRequestDockHeightFraction
                  : null,
              onOpenFile: (path) => unawaited(_openFile(path)),
              onOpenLink: (link) => unawaited(_openLink(link)),
              onOpenArchived: () => unawaited(
                showAgentChatArchivedChats(
                  context,
                  ref,
                  workspace: widget.workspace,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    final view = ref.watch(
      _provider.select(
        (state) => (
          projection: state.projection!,
          canLoadEarlier: state.thread!.historyBefore != null,
          loadingEarlier: state.loadingHistory,
          implementablePlanId: agentChatImplementablePlanId(state),
          title: state.thread!.title,
          provider: state.thread!.provider,
          providerInstanceId: state.thread!.providerInstanceId,
          model: state.thread!.session.model,
          session: state.thread!.session,
          pendingOperation: state.thread!.pendingNativeOperation,
          hint: agentChatEmptyHint(state),
          preparingAttachmentIds: state.preparingAttachmentIds,
        ),
      ),
    );
    final historySupport = watchAgentChatHistorySupport(
      ref,
      session: view.session,
      pendingOperation: view.pendingOperation,
    );
    if (_actions.implementablePlanId != view.implementablePlanId ||
        !sameAgentChatHistorySupport(_historySupport, historySupport)) {
      _historySupport = historySupport;
      _actions = _buildActions(implementablePlanId: view.implementablePlanId);
    }
    if (view.projection.isEmpty && !view.canLoadEarlier) {
      final provider =
          view.provider.isNotEmpty || view.providerInstanceId.isEmpty
          ? view.provider
          : widget.fallbackProvider;
      final instance = ref
          .watch(agentChatProviderCatalogProvider(widget.workspace.id))
          .value
          ?.where((instance) => instance.id == view.providerInstanceId)
          .firstOrNull;
      return AgentChatEmptyConversation(
        title: view.title.isEmpty ? widget.fallbackTitle : view.title,
        provider: provider,
        providerLabel: provider.isEmpty
            ? agentChatNoAgentLabel
            : instance?.label ?? agentChatProviderFallbackLabel(provider),
        model: provider.isEmpty
            ? null
            : agentChatModelLabel(instance, view.model),
        workspacePath: widget.workspace.path,
        hint: view.hint,
      );
    }
    return AgentChatFullDataScope(
      chat: AgentChatRef(
        chatId: widget.chatId,
        workspaceId: widget.workspace.id,
      ),
      child: AgentChatTimelineView(
        projection: view.projection,
        actions: _actions,
        workspacePath: widget.workspace.path,
        canLoadEarlier: view.canLoadEarlier,
        loadingEarlier: view.loadingEarlier,
        onLoadEarlier: () => unawaited(_controller.loadEarlier()),
        preparingAttachmentIds: view.preparingAttachmentIds,
      ),
    );
  }
}
