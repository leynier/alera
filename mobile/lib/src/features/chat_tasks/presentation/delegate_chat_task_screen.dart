import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_detail_screen.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/delegate_chat_task_fields.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_checkout_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens Delegate Task. From Activity the created task opens in its place;
/// from a chat ([initial] names it as parent) the form closes and a SnackBar
/// offers View Task. Its chat and workspace stay one tap away and nothing
/// selects them.
Future<void> openDelegateChatTask(
  BuildContext context,
  String hostId, {
  AgentChatDelegateDraft? initial,
  bool openTaskWhenCreated = true,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => DelegateChatTaskScreen(
      hostId: hostId,
      initial: initial,
      openTaskWhenCreated: openTaskWhenCreated,
    ),
  ),
);

class const DelegateChatTaskScreen({
  super.key,
  required final String hostId,
  final AgentChatDelegateDraft? initial,
  final bool openTaskWhenCreated = true,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<DelegateChatTaskScreen> createState() =>
      _DelegateChatTaskScreenState();
}

class _DelegateChatTaskScreenState
    extends ConsumerState<DelegateChatTaskScreen> {
  late final AgentChatRequestIds _requestIds = AgentChatRequestIds(
    ref.read(mobileChatTaskIdGeneratorProvider),
  );
  late final TextEditingController _task = TextEditingController(
    text: ref.read(mobileDelegateChatTaskFormProvider(widget.hostId)).task,
  );
  late final TextEditingController _title = TextEditingController(
    text: ref.read(mobileDelegateChatTaskFormProvider(widget.hostId)).title,
  );
  bool _sending = false;
  bool _attempted = false;
  String? _error;

  String get _hostId => widget.hostId;

  @override
  void initState() {
    super.initState();
    if (widget.initial case final initial?) {
      ref
          .read(mobileDelegateChatTaskFormProvider(_hostId).notifier)
          .update(initial);
    }
  }

  @override
  void dispose() {
    _task.dispose();
    _title.dispose();
    super.dispose();
  }

  void _edit(AgentChatDelegateDraftEdit edit) {
    final form = mobileDelegateChatTaskFormProvider(_hostId);
    ref.read(form.notifier).update(edit(ref.read(form)));
    if (_error != null) setState(() => _error = null);
  }

  AgentChatDelegateDraft _resolved(
    AgentChatDelegateDraft draft,
    AgentChatOrchestrationCapabilities? catalog,
  ) {
    if (!draft.startsChat || draft.providerInstanceId != null) return draft;
    final provider = catalog?.providers
        .where((item) => item.available)
        .firstOrNull;
    if (provider == null) return draft;
    return draft.copyWith(
      providerInstanceId: provider.id,
      model: draft.model ?? provider.initialModel?.id,
    );
  }

  /// A new workspace needs a host the project is on.
  String? _hostProblem(AgentChatDelegateDraft draft) {
    final projectId = draft.projectId;
    if (draft.targetKind != AgentChatTaskTargetKind.newWorkspace ||
        projectId == null) {
      return null;
    }
    final checkouts = ref
        .read(workspaceCheckoutOptionsProvider(_hostId, projectId))
        .value;
    if (checkouts == null ||
        checkouts.any((checkout) => checkout.hostId == draft.hostId)) {
      return null;
    }
    return 'Choose a host the project is on.';
  }

  Future<void> _submit(AgentChatOrchestrationCapabilities? catalog) async {
    final draft = _resolved(
      ref.read(mobileDelegateChatTaskFormProvider(_hostId)),
      catalog,
    );
    setState(() => _attempted = true);
    if (draft.problem != null || _hostProblem(draft) != null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final actions = await ref.read(
        mobileChatTaskActionsProvider(_hostId).future,
      );
      final result = await actions.delegate(
        draft.toInput(_requestIds.idFor(draft.fingerprint)),
      );
      _requestIds.reset();
      ref.invalidate(mobileDelegateChatTaskFormProvider(_hostId));
      if (!widget.openTaskWhenCreated) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              draft.parentChatId == null
                  ? 'Task delegated. Follow it in Activity.'
                  : 'Task delegated. It reports back to this chat.',
            ),
            action: SnackBarAction(
              label: 'View Task',
              onPressed: () => unawaited(
                navigator.push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatTaskDetailScreen(
                      hostId: _hostId,
                      taskId: result.taskId,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return;
      }
      await navigator.pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              ChatTaskDetailScreen(hostId: _hostId, taskId: result.taskId),
        ),
      );
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
    final draft = ref.watch(mobileDelegateChatTaskFormProvider(_hostId));
    final catalogRead = draft.startsChat
        ? ref.watch(
            mobileChatTaskAgentCatalogProvider(
              _hostId,
              draft.targetKind == AgentChatTaskTargetKind.workspace
                  ? draft.workspaceId
                  : null,
            ),
          )
        : null;
    final catalog = catalogRead?.value;
    final resolved = _resolved(draft, catalog);
    final problem = _attempted
        ? resolved.problem ?? _hostProblem(resolved)
        : null;
    final message = _error ?? problem;
    return Scaffold(
      appBar: AppBar(title: const Text('Delegate Task')),
      body: SafeArea(
        child: ListView(
          padding: AleraTokens.contentPadding,
          children: <Widget>[
            Text(
              draft.parentChatId == null
                  ? 'An agent chat works on this task with the brief you write. It does not see other chats. Nothing opens until you choose to.'
                  : 'An agent chat works on this task with the brief you write. Its result comes back to this chat when it finishes. Nothing opens until you choose to.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.foregroundMuted),
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            AleraTextField(
              key: const ValueKey<String>('delegateTask'),
              controller: _task,
              labelText: 'Task',
              hintText: 'What should the agent do and report back?',
              minLines: 4,
              maxLines: 10,
              enabled: !_sending,
              onChanged: (value) =>
                  _edit((draft) => draft.copyWith(task: value)),
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            AleraTextField(
              key: const ValueKey<String>('delegateTitle'),
              controller: _title,
              labelText: 'Title',
              helperText: 'Shown in Activity; the task text when empty.',
              enabled: !_sending,
              onChanged: (value) =>
                  _edit((draft) => draft.copyWith(title: value)),
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            const AleraSectionHeader(label: 'Run In'),
            DelegateChatTaskTargetFields(
              hostId: _hostId,
              draft: draft,
              onEdit: _edit,
              enabled: !_sending,
            ),
            if (draft.startsChat) ...<Widget>[
              const SizedBox(height: AleraTokens.spaceLg),
              const AleraSectionHeader(label: 'Agent'),
              if (catalog != null)
                DelegateChatTaskAgentFields(
                  catalog: catalog,
                  draft: draft,
                  onEdit: _edit,
                  enabled: !_sending,
                  effortSupported:
                      ref
                          .watch(mobileChatTaskEffortSupportedProvider(_hostId))
                          .value ==
                      true,
                )
              else
                Text(
                  catalogRead?.error == null
                      ? 'Loading agents…'
                      : agentChatOrchestrationErrorMessage(catalogRead!.error!),
                ),
            ],
            if (message != null) ...<Widget>[
              const SizedBox(height: AleraTokens.spaceMd),
              Text(
                message,
                key: const ValueKey<String>('delegateError'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.error),
              ),
            ],
            const SizedBox(height: AleraTokens.spaceLg),
            FilledButton(
              key: const ValueKey<String>('delegateSubmit'),
              onPressed: _sending ? null : () => _submit(catalog),
              child: Text(_sending ? 'Delegating…' : 'Delegate'),
            ),
          ],
        ),
      ),
    );
  }
}
