import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_actions.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/delegate_chat_task_agent_fields.dart';
import 'package:alera/src/features/chat_tasks/presentation/delegate_chat_task_target_fields.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens Delegate Task. From Activity a created task is selected there
/// ([openInActivity]); from a chat it only shows up in that chat's dock or in
/// Activity. Nothing selects its workspace or chat, which stay one press away.
Future<AgentChatDelegateResult?> showDelegateChatTaskDialog(
  BuildContext context, {
  AgentChatDelegateDraft initial = const AgentChatDelegateDraft(),
  bool openInActivity = true,
}) async {
  final container = ProviderScope.containerOf(context);
  final result = await showDialog<AgentChatDelegateResult>(
    context: context,
    builder: (_) => DelegateChatTaskDialog(initial: initial),
  );
  if (result == null || !openInActivity) return result;
  container
      .read(activityNavigationProvider.notifier)
      .openChatTask(result.taskId);
  return result;
}

class const DelegateChatTaskDialog({
  super.key,
  final AgentChatDelegateDraft initial = const AgentChatDelegateDraft(),
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<DelegateChatTaskDialog> createState() =>
      _DelegateChatTaskDialogState();
}

class _DelegateChatTaskDialogState
    extends ConsumerState<DelegateChatTaskDialog> {
  late AgentChatDelegateDraft _draft = widget.initial;
  late final AgentChatRequestIds _requestIds = AgentChatRequestIds(
    ref.read(agentChatIdGeneratorProvider),
  );
  late final TextEditingController _task = TextEditingController(
    text: widget.initial.task,
  );
  late final TextEditingController _title = TextEditingController(
    text: widget.initial.title,
  );
  bool _sending = false;
  bool _attempted = false;
  String? _error;

  @override
  void dispose() {
    _task.dispose();
    _title.dispose();
    super.dispose();
  }

  void _edit(AgentChatDelegateDraftEdit edit) => setState(() {
    _draft = edit(_draft);
    _error = null;
  });

  /// The draft with the catalog's default agent filled in, when the person
  /// kept the one the form shows.
  AgentChatDelegateDraft _resolved(
    AgentChatOrchestrationCapabilities? catalog,
  ) {
    if (!_draft.startsChat || _draft.providerInstanceId != null) return _draft;
    final provider = catalog == null ? null : chatTaskDefaultProvider(catalog);
    if (provider == null) return _draft;
    return _draft.copyWith(
      providerInstanceId: provider.id,
      model: _draft.model ?? provider.initialModel?.id,
    );
  }

  Future<void> _submit(AgentChatOrchestrationCapabilities? catalog) async {
    final draft = _resolved(catalog);
    setState(() => _attempted = true);
    if (draft.problem != null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final input = draft.toInput(_requestIds.idFor(draft.fingerprint));
      final result = await ref.read(chatTaskActionsProvider).delegate(input);
      _requestIds.reset();
      if (mounted) Navigator.of(context).pop(result);
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = agentChatOrchestrationErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workbench = ref.watch(workbenchControllerProvider);
    final projects = workbench.projects;
    List<Workspace> workspacesOf(String? projectId) => <Workspace>[
      for (final project in projects)
        if (projectId == null || project.id == projectId)
          for (final workspace in workbench.workspacesFor(project.id))
            if (workspace.isActive) workspace,
    ];
    final chats = _draft.targetKind == AgentChatTaskTargetKind.chat
        ? ref.watch(chatTaskDirectoryProvider)
        : null;
    final catalogRead = _draft.startsChat
        ? ref.watch(
            chatTaskAgentCatalogProvider(
              _draft.targetKind == AgentChatTaskTargetKind.workspace
                  ? _draft.workspaceId
                  : null,
            ),
          )
        : null;
    final catalog = catalogRead?.value;
    final problem = _attempted ? _resolved(catalog).problem : null;
    return AleraDialog(
      maxWidth: 640,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: 'Delegate Task',
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space4),
            Text(
              _draft.parentChatId == null
                  ? 'An agent chat works on this task with the brief you write. It does not see other chats. Nothing opens until you choose to.'
                  : 'An agent chat works on this task with the brief you write. Its result comes back to this chat when it finishes. Nothing opens until you choose to.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    AleraTextField(
                      key: const ValueKey<String>('delegateTask'),
                      controller: _task,
                      labelText: 'Task',
                      hintText: 'What should the agent do, and what should it report back?',
                      autofocus: true,
                      minLines: 4,
                      maxLines: 10,
                      enabled: !_sending,
                      onChanged: (value) =>
                          _edit((draft) => draft.copyWith(task: value)),
                    ),
                    const SizedBox(height: AleraTokens.space8),
                    AleraTextField(
                      key: const ValueKey<String>('delegateTitle'),
                      controller: _title,
                      labelText: 'Title',
                      hintText: 'Shown in Activity; the task text when empty',
                      enabled: !_sending,
                      onChanged: (value) =>
                          _edit((draft) => draft.copyWith(title: value)),
                    ),
                    const SizedBox(height: AleraTokens.space16),
                    DelegateChatTaskTargetFields(
                      draft: _draft,
                      onEdit: _edit,
                      projects: projects,
                      workspacesOf: workspacesOf,
                      hosts: ref.watch(remoteHostsControllerProvider).hosts,
                      chats: chats?.value,
                      chatsError: chats?.error,
                      enabled: !_sending,
                    ),
                    if (_draft.startsChat) ...<Widget>[
                      const SizedBox(height: AleraTokens.space16),
                      const AleraSectionHeader(label: 'Agent'),
                      if (catalog != null)
                        DelegateChatTaskAgentFields(
                          catalog: catalog,
                          draft: _draft,
                          onEdit: _edit,
                          enabled: !_sending,
                          effortSupported:
                              ref
                                  .watch(chatTaskEffortSupportedProvider)
                                  .value ==
                              true,
                        )
                      else
                        Text(
                          catalogRead?.error == null
                              ? 'Loading agents…'
                              : agentChatOrchestrationErrorMessage(
                                  catalogRead!.error!,
                                ),
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ],
                ),
              ),
            ),
            if ((_error ?? problem) case final message?) ...<Widget>[
              const SizedBox(height: AleraTokens.space12),
              AleraInlineNotice(message: message, tone: .error),
            ],
            const SizedBox(height: AleraTokens.space16),
            Row(
              mainAxisAlignment: .end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  key: const ValueKey<String>('delegateSubmit'),
                  onPressed: _sending ? null : () => _submit(catalog),
                  child: Text(_sending ? 'Delegating…' : 'Delegate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
