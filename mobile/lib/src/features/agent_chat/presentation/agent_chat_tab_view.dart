import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/lifecycle/app_lifecycle_controller.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_tab_actions.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_view_memory.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_availability.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_attachment_picker.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_attachment_upload_bar.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_composer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_native_history_rewind_sheet.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_history_sheets.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_queued_edit.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_request_dock.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tab_body.dart';
import 'package:alera_mobile/src/features/agent_provider_settings/presentation/agent_providers_screen.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_chat_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

part 'agent_chat_tab_drafts.dart';
part 'agent_chat_tab_read_cursor.dart';

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
  final String? remoteHostId,
  final bool autofocus = false,
  final ValueChanged<String>? onOpenTab,
  final ValueChanged<String>? onStartNewChatWithText,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatTabView> createState() => _AgentChatTabViewState();
}

const Uuid _uuid = Uuid();

class _AgentChatTabViewState extends ConsumerState<AgentChatTabView>
    implements AgentChatTabHandlers {
  static final Logger _logger = Logger('AgentChatTabView');

  /// Reading is reported once activity settles, not once per streamed delta.
  static const Duration _readDebounce = Duration(seconds: 1);

  late final AgentChatDraftStore _store;
  late final AgentChatViewMemory _memory;
  late final TextEditingController _composer;
  final FocusNode _focus = FocusNode();
  @override
  final AgentChatQueuedEdit queuedEdit = AgentChatQueuedEdit();
  @override
  final AgentChatTypingClock typing = AgentChatTypingClock();
  @override
  final ValueNotifier<int> scrollToEnd = ValueNotifier<int>(0);
  @override
  final ValueNotifier<AgentChatAttachmentUploadStatus?> upload =
      ValueNotifier<AgentChatAttachmentUploadStatus?>(null);
  List<AgentChatDraftAttachment> _attachments =
      const <AgentChatDraftAttachment>[];
  bool _restoring = false;
  bool _reconciling = false;
  final Map<String, String> _reconcileIds = <String, String>{};
  Timer? _readTimer;

  AgentChatControllerProvider get _provider => agentChatControllerProvider(
    widget.hostId,
    widget.workspaceId,
    widget.chatId,
  );

  @override
  void initState() {
    super.initState();
    _store = ref.read(agentChatDraftStoreProvider)
      ..activate(widget.hostId, widget.chatId, workspaceId: widget.workspaceId);
    _memory = ref
        .read(agentChatViewMemoryStoreProvider)
        .of(widget.hostId, widget.chatId);
    final draft = _store.read(
      widget.hostId,
      widget.chatId,
      workspaceId: widget.workspaceId,
    );
    _composer = TextEditingController.fromValue(draft.value)
      ..addListener(_persist);
    _attachments = draft.attachments;
    _store.addListener(
      widget.hostId,
      widget.chatId,
      _restored,
      workspaceId: widget.workspaceId,
    );
    unawaited(
      _store.hydrate(
        widget.hostId,
        widget.chatId,
        workspaceId: widget.workspaceId,
      ),
    );
    _focus.addListener(() {
      if (!_focus.hasFocus) typing.settle();
    });
    // New Chat focuses the composer it opened; the person asked for it.
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _readTimer?.cancel();
    _store.removeListener(
      widget.hostId,
      widget.chatId,
      _restored,
      workspaceId: widget.workspaceId,
    );
    unawaited(_store.flush());
    _composer
      ..removeListener(_persist)
      ..dispose();
    _focus.dispose();
    queuedEdit.dispose();
    scrollToEnd.dispose();
    upload.dispose();
    super.dispose();
  }

  void _persist() => _persistDraft();
  void _restored() => _restoreStoredDraft();

  @override
  void removeAttachment(AgentChatDraftAttachment attachment) {
    final uploader = AgentChatAttachmentSources.read(
      ref,
      widget.hostId,
      remoteWorkspace: widget.remoteWorkspace,
    ).uploads;
    final chat = AgentChatRef(
      chatId: widget.chatId,
      workspaceId: widget.workspaceId,
    );
    final attachmentId = attachment.attachmentId;
    setState(() {
      _attachments = <AgentChatDraftAttachment>[
        for (final existing in _attachments)
          if (existing != attachment) existing,
      ];
    });
    _persist();
    if (uploader != null && attachmentId != null) {
      unawaited(
        uploader.cancel(chat: chat, uploadId: attachmentId).catchError((
          Object _,
        ) {
          Logger('AgentChatAttachments')
              .fine('Unused attachment cleanup will retry through expiration.');
        }),
      );
    }
  }

  @override
  Future<void> send({bool steer = false}) => _sendDraft(steer: steer);

  /// Runs an action and explains a failure, without leaving the chat.
  @override
  Future<void> run(String what, Future<void> Function() action) async {
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

  /// Edits in place where the runtime can; elsewhere the entry comes back to
  /// the composer, which is the same outcome in two steps.
  @override
  Future<void> editQueued(AgentChatQueueEntry entry) =>
      run('Could not edit the queued message.', () async {
        final controller = ref.read(_provider.notifier);
        final withdrawn = await controller.cancelQueued(entry);
        if (!withdrawn) return;
        _store.restore(
          widget.hostId,
          widget.chatId,
          AgentChatComposerDraft.fromMessage(entry.text, entry.attachments),
          workspaceId: widget.workspaceId,
        );
      });

  /// Opens the message in the composer; Send saves it in place.
  @override
  Future<void> editQueuedInPlace(AgentChatQueueEntry entry) async =>
      _beginQueuedEdit(entry);

  @override
  void cancelQueuedEdit() => _endQueuedEdit();

  @override
  Future<void> reopen() => run('Could not reopen the chat.', () async {
    final actions = await ref.read(
      agentChatTabActionsProvider(widget.hostId).future,
    );
    final result = await actions.reopen(
      workspaceId: widget.workspaceId,
      chatId: widget.chatId,
    );
    final tabId = result.tabId;
    if (tabId != null) widget.onOpenTab?.call(tabId);
  });

  /// Provider Settings opens because the person asked for it from the chat.
  @override
  void openProviderSettings() => unawaited(
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => AgentProvidersScreen(
          hostId: widget.hostId,
          initialRemoteHostId: widget.remoteHostId,
        ),
      ),
    ),
  );

  @override
  VoidCallback? attachHandler(AgentChatViewState view) {
    final capabilities = view.session.capabilities;
    if (!capabilities.attachments && !capabilities.images) return null;
    final sources = AgentChatAttachmentSources.read(
      ref,
      widget.hostId,
      remoteWorkspace: widget.remoteWorkspace,
    );
    if (sources.isEmpty) return null;
    return () => unawaited(_pickAttachments(sources));
  }

  /// Picks and uploads while the composer shows how far the upload got. The
  /// picker reports an upload failure explicitly so Retry stays available.
  Future<void> _pickAttachments(AgentChatAttachmentSources sources) async {
    if (upload.value is AgentChatAttachmentUploading) return;
    upload.value = null;
    final (hostId, chatId, workspaceId) = (
      widget.hostId,
      widget.chatId,
      widget.workspaceId,
    );
    var failed = false;
    await pickAgentChatAttachments(
      context,
      ref,
      hostId: hostId,
      workspaceId: workspaceId,
      chatId: chatId,
      sources: sources,
      onUploadingChanged: (uploading) {
        if (!uploading) return;
        if (mounted) upload.value = const AgentChatAttachmentUploading();
      },
      onProgress: (uploadedBytes, totalBytes) {
        if (!mounted) return;
        upload.value = AgentChatAttachmentUploading(
          uploadedBytes: uploadedBytes,
          totalBytes: totalBytes,
        );
      },
      onUploadFailed: () => failed = true,
    );
    if (!mounted) return;
    upload.value = failed ? const AgentChatAttachmentUploadFailed() : null;
  }

  @override
  void dismissUpload() {
    if (upload.value is AgentChatAttachmentUploadFailed) upload.value = null;
  }

  /// Fork opens the new chat's tab, because the person asked for it.
  @override
  Future<void> fork(String turnId) => run('Could not fork the chat.', () async {
    final result = await ref.read(_provider.notifier).fork(turnId);
    final tabId = result.tabId;
    if (tabId != null) widget.onOpenTab?.call(tabId);
  });

  /// The rewound turn's prompt comes back to the composer, next to anything
  /// already typed there. The sheet offers only the rewinds that exist now
  /// and confirms the chosen one; a file rewind leaves the transcript alone.
  @override
  Future<void> rewind(String turnId, AgentChatRewindOptions options) async {
    final kind = await showAgentChatRewindSheet(context, options: options);
    if (kind == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final controller = ref.read(_provider.notifier);
    await run('Could not rewind the chat.', () async {
      final String notice;
      if (kind == AgentChatRewindKind.files) {
        notice = agentChatFileRewindNotice(
          await controller.rewindFiles(turnId),
        );
      } else {
        final result = await controller.rewind(
          turnId,
          native: kind == AgentChatRewindKind.conversation,
        );
        _store.restore(
          widget.hostId,
          widget.chatId,
          AgentChatComposerDraft.fromMessage(result.prompt, result.attachments),
          workspaceId: widget.workspaceId,
        );
        notice = agentChatRewindResultNotice(result);
      }
      messenger?.showSnackBar(SnackBar(content: Text(notice)));
    });
  }

  /// One request id per chosen action until the runtime answers, so a retry
  /// after a lost answer replays it; nothing retries on its own.
  @override
  Future<void> reconcile(
    AgentChatNativeOperation operation,
    AgentChatNativeHistoryAction action,
  ) async {
    if (_reconciling) return;
    final key = '${operation.operationId}\u0000${action.wire}';
    final requestId = _reconcileIds.putIfAbsent(key, _uuid.v4);
    setState(() => _reconciling = true);
    try {
      await ref
          .read(_provider.notifier)
          .reconcileNativeOperation(operation, action, requestId: requestId);
      _reconcileIds.remove(key);
    } on AgentChatConnectionException catch (error, stackTrace) {
      _report('Could not settle the history change.', error, stackTrace);
    } on Object catch (error, stackTrace) {
      _reconcileIds.remove(key);
      _report('Could not settle the history change.', error, stackTrace);
    } finally {
      if (mounted) setState(() => _reconciling = false);
    }
  }

  @override
  bool get reconciling => _reconciling;

  @override
  Future<void> viewChanges(String turnId) => showAgentChatTurnDiffSheet(
    context,
    load: () => ref.read(_provider.notifier).turnDiff(turnId),
  );

  /// Opens the delegate form prefilled from the plan, targeting a new
  /// workspace; the person reviews it before anything is created.
  @override
  Future<void> implementPlan(AgentChatItem plan) =>
      showImplementPlanInNewWorkspace(
        context,
        hostId: widget.hostId,
        chatId: widget.chatId,
        workspaceId: widget.workspaceId,
        plan: plan,
      );

  @override
  void startNewChatWithText() {
    final text = _store
        .read(widget.hostId, widget.chatId, workspaceId: widget.workspaceId)
        .value
        .text;
    widget.onStartNewChatWithText?.call(text);
  }

  void _scheduleRead(AgentChatViewState view, bool visible) =>
      _scheduleChatRead(view, visible);

  @override
  Widget build(BuildContext context) {
    ref.listen(appLifecycleControllerProvider, (_, next) {
      if (next != AppLifecycleState.resumed) unawaited(_store.flush());
    });
    ref.listen(_provider.select((async) => async.value?.thread.queue), (_, q) {
      if (q != null) _reconcileQueuedEdit(q);
    });
    final async = ref.watch(_provider);
    final view = async.value;
    final lifecycle = ref.watch(appLifecycleControllerProvider);
    final visible =
        lifecycle == AppLifecycleState.resumed &&
        TickerMode.valuesOf(context).enabled;
    final readCursor =
        ref
            .watch(
              agentChatCapabilityProvider(
                widget.hostId,
                AgentChatWire.readCursorCapability,
              ),
            )
            .value ??
        false;
    if (readCursor) {
      ref.listen(_provider, (_, next) {
        if (next.value case final next?) _scheduleRead(next, visible);
      });
    }
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
    return AgentChatTabBody(
      hostId: widget.hostId,
      workspaceId: widget.workspaceId,
      chatId: widget.chatId,
      provider: widget.provider,
      remoteHostId: widget.remoteHostId,
      view: view,
      availability: availability,
      animate: view.turnActive && visible,
      memory: _memory,
      composer: _composer,
      focusNode: _focus,
      attachments: _attachments,
      draftText: _store
          .read(widget.hostId, widget.chatId, workspaceId: widget.workspaceId)
          .value
          .text,
      handlers: this,
      controller: ref.read(_provider.notifier),
      onRetryConnection: () => ref.invalidate(_provider),
      canStartNewChat: widget.onStartNewChatWithText != null,
      minimumComposerHeight: agentChatComposerMinimumHeight(context),
    );
  }
}
