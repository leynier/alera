import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_footer.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_full_data.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_status_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_view.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
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

class _AgentChatSurfaceState extends ConsumerState<AgentChatSurface> {
  final TerminalComposerController _composer = TerminalComposerController();
  final AgentChatExpansion _expansion = AgentChatExpansion();
  late final AgentChatComposerDrafts _drafts;
  late AgentChatTimelineActions _actions;

  AgentChatControllerProvider get _provider =>
      agentChatControllerProvider(widget.chatId, widget.workspace.id);

  @override
  void initState() {
    super.initState();
    _drafts = ref.read(agentChatComposerDraftsProvider);
    _restoreDraft();
    _actions = _buildActions(implementablePlanId: null);
    if (widget.autofocus) _focusComposerNextFrame(onlyIfParked: false);
  }

  @override
  void didUpdateWidget(covariant AgentChatSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) {
      _saveDraft(oldWidget.chatId);
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
    _saveDraft(widget.chatId);
    _composer.dispose();
    super.dispose();
  }

  void _restoreDraft() {
    final draft = _drafts.read(widget.chatId);
    _composer.textController.text = draft.text;
    _composer.removeAttachments(
      _composer.attachments.map((attachment) => attachment.id).toList(),
    );
    for (final attachment in draft.attachments) {
      _composer.addAttachment(
        kind: attachment.kind,
        path: attachment.path,
        displayName: attachment.displayName,
      );
    }
  }

  void _saveDraft(String chatId) => _drafts.write(
    chatId,
    AgentChatComposerDraft(
      text: _composer.textController.text,
      attachments: List.unmodifiable(_composer.attachments),
    ),
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
    onRespond: (request, response) =>
        unawaited(_controller.respond(request, response)),
    onRetrySend: (id) => unawaited(_controller.retrySend(id)),
    onEditSend: _editFailedSend,
    onOpenLink: (link) => unawaited(_openLink(link)),
    onOpenFile: (path) => unawaited(_openFile(path)),
    onImplementPlan: () => unawaited(_implementPlan()),
    implementablePlanId: implementablePlanId,
  );

  void _editFailedSend(String clientMessageId) {
    final message = _controller.discardSend(clientMessageId);
    if (message == null) return;
    final draft = _composer.textController.text;
    final text = message.text.isEmpty
        ? draft
        : draft.isEmpty
        ? message.text
        : '$draft\n\n${message.text}';
    _composer.textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    for (final attachment in message.attachments) {
      final path = attachment.path;
      if (path == null) continue;
      final kind = attachment.type.isImage
          ? TerminalComposerAttachmentKind.image
          : TerminalComposerAttachmentKind.file;
      if (_composer.attachments.any(
        (current) => current.path == path && current.kind == kind,
      )) {
        continue;
      }
      _composer.addAttachment(
        kind: kind,
        path: path,
        displayName: attachment.displayName,
      );
    }
    if (draft.isNotEmpty) {
      AleraToast.publish(
        message: 'The failed message was added to your draft.',
      );
    }
    _composer.focusNode.requestFocus();
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: _buildTimeline()),
          AgentChatFooter(
            chatId: widget.chatId,
            workspace: widget.workspace,
            fallbackProvider: widget.fallbackProvider,
            composer: _composer,
            onOpenFile: (path) => unawaited(_openFile(path)),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final view = ref.watch(
      _provider.select(
        (state) => (
          projection: state.projection!,
          responding: state.respondingRequestIds,
          enabled: state.canSend,
          canLoadEarlier: state.thread!.historyBefore != null,
          loadingEarlier: state.loadingHistory,
          implementablePlanId: _implementablePlanId(state),
          title: state.thread!.title,
          provider: state.thread!.provider,
          model: state.thread!.session.model,
          hint: agentChatEmptyHint(state),
        ),
      ),
    );
    if (_actions.implementablePlanId != view.implementablePlanId) {
      _actions = _buildActions(implementablePlanId: view.implementablePlanId);
    }
    if (view.projection.isEmpty && !view.canLoadEarlier) {
      final provider = view.provider.isEmpty
          ? widget.fallbackProvider
          : view.provider;
      return AgentChatEmptyConversation(
        title: view.title.isEmpty ? widget.fallbackTitle : view.title,
        provider: provider,
        providerLabel:
            ref
                .watch(agentChatProviderCatalogProvider(widget.workspace.id))
                .value
                ?.where((instance) => instance.provider == provider)
                .firstOrNull
                ?.label ??
            agentChatProviderFallbackLabel(provider),
        model: view.model,
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
        expansion: _expansion,
        respondingRequestIds: view.responding,
        enabled: view.enabled,
        workspacePath: widget.workspace.path,
        canLoadEarlier: view.canLoadEarlier,
        loadingEarlier: view.loadingEarlier,
        onLoadEarlier: () => unawaited(_controller.loadEarlier()),
      ),
    );
  }
}

/// The plan an "Implement Plan" button may act on: the newest proposed plan
/// of the latest turn, while the chat is idle in plan mode.
String? _implementablePlanId(AgentChatViewState state) {
  final thread = state.thread;
  final projection = state.projection;
  if (thread == null ||
      projection == null ||
      thread.session.busy ||
      thread.session.interactionMode != AgentChatInteractionMode.plan) {
    return null;
  }
  for (final entry in projection.entries.reversed) {
    if (entry is! AgentChatTurnEntry) continue;
    for (final answer in entry.section.answers.reversed) {
      if (answer.type == AgentChatItemType.plan && !answer.isInProgress) {
        return answer.id;
      }
    }
    return null;
  }
  return null;
}
