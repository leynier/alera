import 'package:alera_mobile/src/features/automations/domain/mobile_automation.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_editor.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_widgets.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter/material.dart';

class const MobileAutomationDetailActions({
  required final MobileAutomationDetail detail,
  required final MobileRuntimeAutomationRepository repository,
  required final MobileRuntimeClient client,
  required final VoidCallback onChanged,
}) {
  Future<void> approve(BuildContext context) async {
    try {
      await repository.approve(
        detail.automation.id,
        detail.automation.revision,
      );
      onChanged();
    } on Object catch (error) {
      if (context.mounted) showMessage(context, error.toString(), error: true);
    }
  }

  Future<void> trashOrRestore(BuildContext context) async {
    try {
      if (detail.automation.state == 'trashed') {
        await repository.restore(detail.automation.id);
      } else {
        await repository.trash(detail.automation.id);
      }
      onChanged();
      if (context.mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (context.mounted) showMessage(context, error.toString(), error: true);
    }
  }

  Future<void> clone(BuildContext context) async {
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
      initial: .fromJson(raw),
      options: options,
    );
    if (definition != null) {
      await repository.upsert(definition);
      onChanged();
    }
  }

  Future<void> showTemplates(BuildContext context) async {
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
        initial: .fromJson(raw),
        options: options,
      );
      if (definition != null) {
        await repository.upsert(definition);
        onChanged();
      }
    } on Object catch (error) {
      if (context.mounted) showMessage(context, error.toString(), error: true);
    }
  }

  Future<void> editTags(BuildContext context) async {
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
      if (context.mounted) showMessage(context, error.toString(), error: true);
    } finally {
      controller.dispose();
    }
  }

  Future<void> editPolicies(BuildContext context) async {
    final profileId = detail.effectivePolicies['targetProfileId']?.toString();
    final project = mapValue(detail.effectivePolicies['project']);
    final projectId = project['projectId']?.toString();
    if (profileId == null && projectId == null) {
      showMessage(
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
            profile: mapValue(detail.effectivePolicies['targetProfile']),
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
      if (context.mounted) showMessage(context, error.toString(), error: true);
    }
  }

  Future<void> cancel(BuildContext context, Map<String, Object?> run) async {
    final identity = targetIdentity(run);
    if (identity.isEmpty) {
      showMessage(context, 'The run target identity is missing.', error: true);
      return;
    }
    try {
      await repository.cancel('${run['id']}', identity);
      onChanged();
    } on Object catch (error) {
      if (context.mounted) showMessage(context, error.toString(), error: true);
    }
  }

  Future<void> setWaiting(
    BuildContext context,
    Map<String, Object?> run, {
    required bool waiting,
  }) async {
    final identity = targetIdentity(run);
    if (identity.isEmpty) {
      showMessage(context, 'The run target identity is missing.', error: true);
      return;
    }
    try {
      await repository.wait('${run['id']}', identity, waiting: waiting);
      onChanged();
    } on Object catch (error) {
      if (context.mounted) showMessage(context, error.toString(), error: true);
    }
  }

  Future<void> extend(BuildContext context, Map<String, Object?> run) async {
    try {
      await repository.extend(
        '${run['id']}',
        targetIdentity(run),
        seconds: 3600,
      );
      onChanged();
    } on Object catch (error) {
      if (context.mounted) showMessage(context, error.toString(), error: true);
    }
  }

  static bool isActive(Object? value) => <String>{
    'pending',
    'dispatching',
    'dispatched',
    'waitingForUser',
    'cancellationRequested',
  }.contains(value);

  static Map<String, Object?> targetIdentity(Map<String, Object?> run) {
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

  static Map<String, Object?> mapValue(Object? value) => value is Map
      ? <String, Object?>{
          for (final entry in value.entries)
            if (entry.key is String) entry.key as String: entry.value,
        }
      : <String, Object?>{};

  static void showMessage(
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
}
