import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/automations/domain/mobile_automation.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_editor.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_widgets.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter/material.dart';

class MobileAutomationDetailSheet extends StatelessWidget {
  const MobileAutomationDetailSheet({
    required this.detail,
    required this.repository,
    required this.client,
    required this.onChanged,
    super.key,
  });

  final MobileAutomationDetail detail;
  final MobileRuntimeAutomationRepository repository;
  final MobileRuntimeClient client;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final automation = detail.automation;
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
                  onPressed: () => unawaited(_clone(context)),
                  icon: const Icon(Icons.copy),
                  label: const Text('Clone'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_showTemplates(context)),
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Templates'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_editTags(context)),
                  icon: const Icon(Icons.sell_outlined),
                  label: const Text('Tags'),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_editPolicies(context)),
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
                trailing: _isActive(run['status'])
                    ? Wrap(
                        children: <Widget>[
                          if (run['status'] == 'waitingForUser')
                            IconButton(
                              tooltip: 'Resume Waiting Run',
                              icon: const Icon(Icons.play_arrow),
                              onPressed: () => unawaited(
                                _setWaiting(context, run, waiting: false),
                              ),
                            ),
                          if (run['status'] == 'waitingForUser')
                            IconButton(
                              tooltip: 'Extend Waiting Run',
                              icon: const Icon(Icons.more_time),
                              onPressed: () => unawaited(_extend(context, run)),
                            ),
                          IconButton(
                            tooltip: 'Cancel',
                            icon: const Icon(Icons.cancel_outlined),
                            onPressed: () => unawaited(_cancel(context, run)),
                          ),
                        ],
                      )
                    : null,
              ),
            if (!automation.isApproved)
              FilledButton(
                onPressed: () async {
                  await repository.approve(automation.id, automation.revision);
                  onChanged();
                },
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
                  (run) => _isActive(run['status']),
                )) {
                  final identity = _targetIdentity(run);
                  if (identity.isNotEmpty) {
                    await repository.cancel('${run['id']}', identity);
                  }
                }
                onChanged();
              },
              child: const Text('Cancel Active Runs'),
            ),
            OutlinedButton(
              onPressed: () async {
                if (automation.state == 'trashed') {
                  await repository.restore(automation.id);
                } else {
                  await repository.trash(automation.id);
                }
                onChanged();
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(automation.state == 'trashed' ? 'Restore' : 'Trash'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clone(BuildContext context) async {
    final raw = <String, Object?>{
      ...detail.automation.raw,
      'id': 'mobile-${DateTime.now().microsecondsSinceEpoch}',
      'slug': '${detail.automation.slug}-copy',
      'state': 'draft',
      'revision': 0,
      'approvedRevision': null,
    };
    final options = await loadMobileAutomationEditorOptions(client);
    if (!context.mounted) return;
    final definition = await showMobileAutomationEditor(
      context,
      initial: MobileAutomation.fromJson(raw),
      options: options,
    );
    if (definition != null) {
      await repository.upsert(definition);
      onChanged();
    }
  }

  Future<void> _showTemplates(BuildContext context) async {
    try {
      final templates = await repository.templates();
      if (!context.mounted) return;
      final selected = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Automation Templates'),
          content: SizedBox(
            width: 420,
            child: templates.isEmpty
                ? const Text('No templates are saved.')
                : ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final template in templates)
                        ListTile(
                          title: Text('${template['name'] ?? 'Template'}'),
                          subtitle: Text('${template['promptTemplate'] ?? ''}'),
                          onTap: () => Navigator.pop(context, <String, Object?>{
                            for (final entry in template.entries)
                              entry.key: entry.value,
                          }),
                        ),
                    ],
                  ),
          ),
        ),
      );
      if (selected == null || !context.mounted) return;
      final options = await loadMobileAutomationEditorOptions(client);
      if (!context.mounted) return;
      final raw = <String, Object?>{
        ...detail.automation.raw,
        if (selected['promptTemplate'] is String)
          'promptTemplate': selected['promptTemplate'],
        if (selected['description'] is String)
          'description': selected['description'],
      };
      final definition = await showMobileAutomationEditor(
        context,
        initial: MobileAutomation.fromJson(raw),
        options: options,
      );
      if (definition != null) {
        await repository.upsert(definition);
        onChanged();
      }
    } on Object catch (error) {
      if (context.mounted) _show(context, error.toString(), error: true);
    }
  }

  Future<void> _editTags(BuildContext context) async {
    final controller = TextEditingController(
      text: detail.automation.tagIds.join(', '),
    );
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Automation Tags'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Tag Ids',
              helperText: 'Use comma-separated existing tag ids.',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (value == null) return;
      await repository.setTags(
        detail.automation.id,
        value
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(),
      );
      onChanged();
    } on Object catch (error) {
      if (context.mounted) _show(context, error.toString(), error: true);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _editPolicies(BuildContext context) async {
    final profileId = detail.effectivePolicies['targetProfileId']?.toString();
    final project = _map(detail.effectivePolicies['project']);
    final projectId = project['projectId']?.toString();
    if (profileId == null && projectId == null) {
      _show(
        context,
        'No target profile or project policy is available.',
        error: true,
      );
      return;
    }
    final result =
        await showDialog<
          ({bool activate, bool execute, bool restrictive, bool local})
        >(
          context: context,
          builder: (_) => MobilePolicyDialog(
            profile: _map(detail.effectivePolicies['targetProfile']),
            project: project,
          ),
        );
    if (result == null) return;
    try {
      if (profileId != null) {
        await repository.policy(
          kind: 'agent',
          profileId: profileId,
          value: <String, Object?>{
            'mayActivateOrEditActive': result.activate,
            'mayExecute': result.execute,
          },
        );
      }
      if (projectId != null) {
        await repository.policy(
          kind: 'project',
          projectId: projectId,
          value: <String, Object?>{
            'restrictive': result.restrictive,
            'localApproved': result.local,
          },
        );
      }
      onChanged();
    } on Object catch (error) {
      if (context.mounted) _show(context, error.toString(), error: true);
    }
  }

  static bool _isActive(Object? value) => <String>{
    'pending',
    'dispatching',
    'dispatched',
    'waitingForUser',
    'cancellationRequested',
  }.contains(value);

  static Map<String, Object?> _targetIdentity(Map<String, Object?> run) {
    final value = run['targetIdentity'];
    if (value is! Map) return const <String, Object?>{};
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String &&
            entry.value is String &&
            (entry.value as String).isNotEmpty)
          entry.key as String: entry.value,
    };
  }

  static Map<String, Object?> _map(Object? value) => value is Map
      ? <String, Object?>{
          for (final entry in value.entries)
            if (entry.key is String) entry.key as String: entry.value,
        }
      : <String, Object?>{};

  static void _show(
    BuildContext context,
    String message, {
    bool error = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  Future<void> _cancel(BuildContext context, Map<String, Object?> run) async {
    final identity = _targetIdentity(run);
    if (identity.isEmpty) {
      _show(context, 'The run target identity is missing.', error: true);
      return;
    }
    try {
      await repository.cancel('${run['id']}', identity);
      onChanged();
    } on Object catch (error) {
      if (context.mounted) _show(context, error.toString(), error: true);
    }
  }

  Future<void> _setWaiting(
    BuildContext context,
    Map<String, Object?> run, {
    required bool waiting,
  }) async {
    final identity = _targetIdentity(run);
    if (identity.isEmpty) {
      _show(context, 'The run target identity is missing.', error: true);
      return;
    }
    try {
      await repository.wait('${run['id']}', identity, waiting: waiting);
      onChanged();
    } on Object catch (error) {
      if (context.mounted) _show(context, error.toString(), error: true);
    }
  }

  Future<void> _extend(BuildContext context, Map<String, Object?> run) async {
    try {
      await repository.extend(
        '${run['id']}',
        _targetIdentity(run),
        seconds: 3600,
      );
      onChanged();
    } on Object catch (error) {
      if (context.mounted) _show(context, error.toString(), error: true);
    }
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
