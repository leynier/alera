import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/automations/domain/mobile_automation.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_detail_actions.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_editor.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter/material.dart';

class const MobileAutomationDetailSheet({
  required this.detail,
  required this.repository,
  required this.client,
  required this.onChanged,
  this.initialRunId,
  super.key,
}) extends StatefulWidget {
  final MobileAutomationDetail detail;
  final MobileRuntimeAutomationRepository repository;
  final MobileRuntimeClient client;
  final VoidCallback onChanged;
  final String? initialRunId;

  @override
  State<MobileAutomationDetailSheet> createState() =>
      _MobileAutomationDetailSheetState();
}

class _MobileAutomationDetailSheetState
    extends State<MobileAutomationDetailSheet> {
  late MobileAutomationDetail _detail;

  @override
  void initState() {
    super.initState();
    _detail = widget.detail;
  }

  Future<void> _reloadAfterChange() async {
    widget.onChanged();
    try {
      final next = await widget.repository.show(_detail.automation.id);
      if (mounted) setState(() => _detail = next);
    } on Object {
      // The catalog already refreshed; keep the current sheet contents.
    }
  }

  @override
  Widget build(BuildContext context) {
    return _MobileAutomationDetailBody(
      detail: _detail,
      repository: widget.repository,
      client: widget.client,
      onChanged: () => unawaited(_reloadAfterChange()),
      initialRunId: widget.initialRunId,
    );
  }
}

class const _MobileAutomationDetailBody({
  required final MobileAutomationDetail detail,
  required final MobileRuntimeAutomationRepository repository,
  required final MobileRuntimeClient client,
  required final VoidCallback onChanged,
  final String? initialRunId,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final automation = detail.automation;
    final actions = MobileAutomationDetailActions(
      detail: detail,
      repository: repository,
      client: client,
      onChanged: onChanged,
    );
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: AleraTokens.pagePadding,
          children: <Widget>[
            Text(
              automation.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (initialRunId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
                child: Text(
                  'Opened from run $initialRunId',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Text(automation.promptTemplate),
            const SizedBox(height: AleraTokens.spaceSm),
            Text(
              'Prompt Preview',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SelectableText(_promptPreview(automation)),
            const SizedBox(height: AleraTokens.spaceMd),
            Wrap(
              spacing: AleraTokens.spaceSm,
              runSpacing: AleraTokens.spaceSm,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () => unawaited(actions.clone(context)),
                  icon: const Icon(Icons.copy),
                  label: const Text('Clone'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(actions.showTemplates(context)),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Templates'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(actions.editTags(context)),
                  icon: const Icon(Icons.sell_outlined),
                  label: const Text('Tags'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(actions.editPolicies(context)),
                  icon: const Icon(Icons.policy_outlined),
                  label: const Text('Policies'),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            Text(
              'Effective Policy',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final entry in detail.effectivePolicies.entries)
              ListTile(
                title: Text(entry.key),
                subtitle: Text('${entry.value}'),
              ),
            Text('Audit', style: Theme.of(context).textTheme.titleMedium),
            for (final event in detail.audit)
              ListTile(
                dense: true,
                title: Text('${event['action'] ?? 'Changed'}'),
                subtitle: Text('${event['createdAt'] ?? ''}'),
              ),
            Text('Timeline', style: Theme.of(context).textTheme.titleMedium),
            for (final occurrence in detail.occurrences.take(5))
              ListTile(
                title: Text(
                  '${occurrence['localTime'] ?? occurrence['scheduledAt'] ?? 'Upcoming'}',
                ),
              ),
            Text('Runs', style: Theme.of(context).textTheme.titleMedium),
            for (final run in detail.runs)
              ListTile(
                title: Text('${run['status'] ?? 'Unknown'}'),
                subtitle: Text('${run['summary'] ?? run['error'] ?? ''}'),
                trailing: MobileAutomationDetailActions.isActive(run['status'])
                    ? Wrap(
                        children: <Widget>[
                          if (run['status'] == 'waitingForUser')
                            IconButton(
                              tooltip: 'Resume Waiting Run',
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () => unawaited(
                                actions.setWaiting(
                                  context,
                                  run,
                                  waiting: false,
                                ),
                              ),
                            ),
                          if (run['status'] == 'waitingForUser')
                            IconButton(
                              tooltip: 'Extend Waiting Run',
                              icon: const Icon(Icons.more_time),
                              onPressed: () =>
                                  unawaited(actions.extend(context, run)),
                            ),
                          IconButton(
                            tooltip: 'Cancel',
                            icon: const Icon(Icons.cancel_outlined),
                            onPressed: () =>
                                unawaited(actions.cancel(context, run)),
                          ),
                        ],
                      )
                    : null,
              ),
            if (!automation.isApproved)
              FilledButton(
                onPressed: () => unawaited(actions.approve(context)),
                child: const Text('Approve Revision'),
              ),
            FilledButton(
              onPressed: () async {
                final options = await loadMobileAutomationEditorOptions(client);
                if (!context.mounted) return;
                final definition = await showMobileAutomationEditor(
                  context,
                  initial: automation,
                  options: options,
                );
                if (definition != null) {
                  await repository.upsert(definition);
                  onChanged();
                }
              },
              child: const Text('Edit'),
            ),
            OutlinedButton(
              onPressed: () async {
                for (final run in detail.runs.where(
                  (run) =>
                      MobileAutomationDetailActions.isActive(run['status']),
                )) {
                  final identity = MobileAutomationDetailActions.targetIdentity(
                    run,
                  );
                  if (identity.isNotEmpty) {
                    await repository.cancel('${run['id']}', identity);
                  }
                }
                onChanged();
              },
              child: const Text('Cancel Active Runs'),
            ),
            OutlinedButton(
              onPressed: () => unawaited(actions.trashOrRestore(context)),
              child: Text(automation.state == 'trashed' ? 'Restore' : 'Trash'),
            ),
          ],
        ),
      ),
    );
  }
}

String _promptPreview(MobileAutomation automation) {
  const known = <String>{
    'automation.id',
    'automation.name',
    'automation.slug',
    'run.id',
    'run.number',
    'run.scheduledAt',
    'workspace.id',
    'workspace.name',
    'workspace.path',
    'project.id',
    'project.name',
  };
  final values = <String, String>{
    'automation.id': automation.id,
    'automation.name': automation.name,
    'automation.slug': automation.slug,
  };
  var invalid = <String>[];
  final rendered = automation.promptTemplate.replaceAllMapped(
    RegExp(r'\{\{([^}]+)\}\}'),
    (match) {
      final variable = match.group(1)!.trim();
      if (!known.contains(variable)) {
        invalid = <String>[...invalid, variable];
        return match.group(0)!;
      }
      return values[variable] ?? '<$variable>';
    },
  );
  if (invalid.isNotEmpty) {
    return 'Unknown prompt variable: ${invalid.toSet().join(', ')}';
  }
  return rendered;
}
