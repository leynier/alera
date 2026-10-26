import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_relationships.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_activity_rows.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_settings.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_subagent_bar.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_subagent_scope.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_workflow_panel.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_workspace_file_opener.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A provider-native sub-agent opened in place of its chat, read-only: what
/// it was asked, its own work, its result, and the sub-agent bar where the
/// composer would be. Work streams in from the chat as it happens; older
/// work the chat has not loaded comes from `agentChat.subagent`.
class const AgentChatSubagentSurface({
  super.key,
  required final String chatId,
  required final Workspace workspace,
  required final String callId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatSubagentSurface> createState() =>
      _AgentChatSubagentSurfaceState();
}

class _AgentChatSubagentSurfaceState
    extends ConsumerState<AgentChatSubagentSurface> {
  final AgentChatExpansion _expansion = AgentChatExpansion();
  late final AgentChatTimelineActions _actions = AgentChatTimelineActions(
    chatId: widget.chatId,
    onRetrySend: (_) {},
    onEditSend: (_) {},
    onOpenLink: (link) => unawaited(_openLink(link)),
    onOpenFile: (path) => unawaited(_openFile(path)),
    onImplementPlan: () {},
  );

  AgentChatControllerProvider get _chat =>
      agentChatControllerProvider(widget.chatId, widget.workspace.id);

  AgentChatOpenSubagentProvider get _open =>
      agentChatOpenSubagentProvider(widget.chatId);

  Future<void> _openFile(String path) async {
    try {
      await openTerminalComposerWorkspaceFile(
        ref,
        widget.workspace.id,
        path,
        sourceKey: 'chat:${widget.chatId}',
      );
    } on Object catch (error) {
      AleraToast.publish(message: 'Could not open $path: $error', tone: .error);
    }
  }

  Future<void> _openLink(String link) async {
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return;
    if (!uri.hasScheme) return _openFile(uri.path);
    if (!const <String>{'http', 'https', 'mailto'}.contains(uri.scheme)) {
      AleraToast.publish(message: 'This link cannot be opened from a chat.');
      return;
    }
    await UrlLauncherExternalUriLauncher().open(uri);
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(_chat.select((state) => state.thread?.items));
    final provider = ref.watch(
      _chat.select((state) => state.thread?.provider ?? ''),
    );
    final instanceId = ref.watch(
      _chat.select((state) => state.thread?.providerInstanceId ?? ''),
    );
    final title = ref.watch(_chat.select((state) => state.thread?.title));
    final stored = ref.watch(
      agentChatSubagentTranscriptProvider(
        widget.chatId,
        widget.workspace.id,
        widget.callId,
      ),
    );
    final live = items ?? const <AgentChatItem>[];
    final transcript = stored.value;
    final call =
        live.where((item) => item.id == widget.callId).firstOrNull ??
        transcript?.call;
    if (call == null) {
      return ColoredBox(
        color: AleraTokens.bg,
        child: Center(
          child: stored.hasError
              ? Text(
                  agentChatErrorMessage(stored.error!),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : const CircularProgressIndicator(),
        ),
      );
    }
    final merged = <String, AgentChatItem>{
      for (final item in transcript?.items ?? const <AgentChatItem>[])
        item.id: item,
    };
    for (final item in agentChatSubagentDescendants(live, widget.callId)) {
      merged[item.id] = item;
    }
    final timeline = AgentChatSubagentTimeline.build(
      call,
      merged.values.toList(),
    );
    final instance = ref
        .watch(agentChatProviderCatalogProvider(widget.workspace.id))
        .value
        ?.where((candidate) => candidate.id == instanceId)
        .firstOrNull;
    final effort = call.subagentReasoningEffort;
    final parentCall = call.parentItemId;
    return ColoredBox(
      color: AleraTokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header(
            chatTitle: (title?.trim().isEmpty ?? true) ? 'Chat' : title!,
            timeline: timeline,
            onBack: ref.read(_open.notifier).close,
          ),
          const Divider(height: AleraTokens.dividerExtent),
          Expanded(
            child: ListView(
              key: ValueKey<String>('agent-chat-subagent-${widget.callId}'),
              padding: const EdgeInsets.all(AleraTokens.space16),
              children: <Widget>[
                if (transcript?.truncated ?? false)
                  const _Notice(
                    'Earlier work of this sub-agent is beyond what the '
                    'runtime reads at once.',
                  ),
                if (timeline.prompt case final prompt?) _Prompt(prompt),
                if (call.workflowGroup case final workflow?)
                  AgentChatWorkflowPanel(callId: call.id, group: workflow),
                if (timeline.rows.isEmpty &&
                    timeline.running &&
                    call.subagent?.workflow == null)
                  const _Notice('The sub-agent has not reported work yet.'),
                for (final row in timeline.rows)
                  AgentChatActivityRowView(
                    key: ValueKey<String>(row.key),
                    row: row,
                    expansion: _expansion,
                    actions: _actions,
                    workspacePath: widget.workspace.path,
                  ),
                if (timeline.summary case final summary?)
                  Padding(
                    padding: const EdgeInsets.only(top: AleraTokens.space12),
                    child: AgentChatMarkdown(
                      data: summary,
                      onOpenLink: (link) => unawaited(_openLink(link)),
                    ),
                  ),
              ],
            ),
          ),
          AgentChatSubagentBar(
            provider: provider,
            call: call,
            modelLabel: agentChatModelLabel(instance, call.subagentModel),
            effortLabel: effort == null ? null : agentChatEffortLabel(effort),
            onOpenParent: () {
              // A nested sub-agent's parent is the sub-agent that started it.
              final notifier = ref.read(_open.notifier);
              final parent = parentCall == null
                  ? null
                  : live.where((item) => item.id == parentCall).firstOrNull;
              parent != null && parent.startsSubagent
                  ? notifier.open(parent.id)
                  : notifier.close();
            },
          ),
        ],
      ),
    );
  }
}

class const _Header({
  required final String chatTitle,
  required final AgentChatSubagentTimeline timeline,
  required final VoidCallback onBack,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scope = AgentChatSubagentScope.maybeOf(context);
    final stop = scope?.onStop;
    final stopping = scope?.stopping.contains(timeline.call.id) ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space6,
      ),
      child: Row(
        children: <Widget>[
          AleraIconButton(
            key: const ValueKey<String>('agent-chat-subagent-back'),
            tooltip: 'Back to Chat',
            icon: AleraIcons.back,
            onPressed: onBack,
          ),
          const SizedBox(width: AleraTokens.space8),
          Flexible(
            child: Text(
              chatTitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(
            AleraIcons.chevronRight,
            size: AleraTokens.iconMd,
            color: AleraTokens.foregroundFaint,
          ),
          const Icon(AleraIcons.agent, size: AleraTokens.iconMd),
          const SizedBox(width: AleraTokens.space6),
          Expanded(
            child: Text(
              timeline.label,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (timeline.running && stop != null)
            TextButton.icon(
              key: const ValueKey<String>('agent-chat-subagent-stop'),
              onPressed: stopping ? null : () => stop(timeline.call.id),
              icon: const Icon(AleraIcons.stop, size: AleraTokens.iconMd),
              label: Text(
                timeline.call.subagent?.workflow == null
                    ? 'Stop Sub-agent'
                    : 'Stop Workflow',
              ),
            ),
        ],
      ),
    );
  }
}

class const _Prompt(final String prompt) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AleraTokens.space12),
    padding: const EdgeInsets.all(AleraTokens.space12),
    decoration: BoxDecoration(
      color: AleraTokens.surface,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    ),
    child: SelectableText(prompt, style: Theme.of(context).textTheme.bodySmall),
  );
}

class const _Notice(final String text) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.space8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AleraTokens.foregroundFaint),
    ),
  );
}
