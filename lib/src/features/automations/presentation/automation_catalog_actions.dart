import 'dart:async';
import 'dart:convert';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/presentation/authoring/automation_authoring_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _CatalogAction { templates, import, export }

/// Templates, import and export, kept out of the main toolbar.
class const AutomationCatalogMenu({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_CatalogAction>(
      tooltip: 'Templates, Import And Export',
      icon: const Icon(AleraIcons.more),
      onSelected: (action) => unawaited(switch (action) {
        _CatalogAction.templates => _useTemplate(context, ref),
        _CatalogAction.import => _importCatalog(context, ref),
        _CatalogAction.export => _exportCatalog(ref),
      }),
      itemBuilder: (_) => const <PopupMenuEntry<_CatalogAction>>[
        AleraDropdownEntry(
          value: _CatalogAction.templates,
          leading: Icon(AleraIcons.file, size: 16),
          label: 'New From Template',
        ),
        AleraDropdownEntry(
          value: _CatalogAction.import,
          leading: Icon(AleraIcons.download, size: 16),
          label: 'Import Automations',
        ),
        AleraDropdownEntry(
          value: _CatalogAction.export,
          leading: Icon(AleraIcons.cloudUpload, size: 16),
          label: 'Copy Catalog As JSON',
        ),
      ],
    );
  }
}

Future<void> saveAutomationTemplate(
  WidgetRef ref,
  AutomationRecord automation,
) async {
  try {
    await ref.read(automationRepositoryProvider).saveTemplate(<String, Object?>{
      'id': 'template-${DateTime.now().microsecondsSinceEpoch}',
      'name': automation.name,
      'promptTemplate': automation.promptTemplate,
      'description': automation.description,
      'projectId': automation.projectId,
      'tagIds': automation.tagIds,
      'createdBy':
          automation.raw['createdBy'] ??
          const <String, Object?>{'kind': 'humanDesktop'},
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    AleraToast.publish(
      message: 'Saved "${automation.name}" as a template.',
      tone: AleraToastTone.success,
    );
  } catch (error) {
    AleraToast.publish(message: '$error', tone: AleraToastTone.error);
  }
}

Future<void> _useTemplate(BuildContext context, WidgetRef ref) async {
  try {
    final templates = await ref.read(automationRepositoryProvider).templates();
    if (!context.mounted) return;
    final selected = await showDialog<JsonMap>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New From Template'),
        content: SizedBox(
          width: 420,
          child: templates.isEmpty
              ? const Text(
                  'No templates are saved. Use Save As Template on an automation first.',
                )
              : ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final template in templates)
                      ListTile(
                        title: Text('${template['name'] ?? 'Template'}'),
                        subtitle: Text(
                          '${template['promptTemplate'] ?? ''}',
                          maxLines: 2,
                          overflow: .ellipsis,
                        ),
                        onTap: () => Navigator.of(dialogContext).pop(template),
                      ),
                  ],
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    await showAutomationAuthoringDialog(
      context,
      ref,
      request: AutomationAuthoringRequest(template: selected),
    );
  } catch (error) {
    AleraToast.publish(message: '$error', tone: AleraToastTone.error);
  }
}

Future<void> _exportCatalog(WidgetRef ref) async {
  try {
    final bundle = await ref.read(automationRepositoryProvider).exportCatalog();
    await Clipboard.setData(ClipboardData(text: jsonEncode(bundle)));
    AleraToast.publish(
      message: 'Automation catalog copied to the clipboard.',
      tone: AleraToastTone.success,
    );
  } catch (error) {
    AleraToast.publish(message: '$error', tone: AleraToastTone.error);
  }
}

Future<void> _importCatalog(BuildContext context, WidgetRef ref) async {
  final text = await _askForText(
    context,
    title: 'Import Automations',
    label: 'Versioned JSON Catalog',
    confirm: 'Import',
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('The catalog JSON must be an object.');
    }
    final bundle = automationJsonMap(decoded);
    final keys = automationPortableCatalogKeys(bundle).toList()..sort();
    var remap = const <String, String>{};
    if (keys.isNotEmpty) {
      final mapping = await _askForText(
        context,
        title: 'Map Imported Targets',
        label: 'Source Key To Local Id JSON',
        confirm: 'Continue',
        initial: jsonEncode(<String, String>{for (final key in keys) key: ''}),
      );
      if (mapping == null) return;
      final decodedMapping = jsonDecode(mapping);
      if (decodedMapping is! Map) {
        throw const FormatException('The mapping must be a JSON object.');
      }
      remap = <String, String>{
        for (final entry in decodedMapping.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: (entry.value as String).trim(),
      };
    }
    await ref.read(automationRepositoryProvider).importCatalog(bundle, remap);
    ref.invalidate(automationCatalogProvider);
    AleraToast.publish(
      message: 'Automation catalog imported. Imported automations arrive as drafts; activate them when ready.',
      tone: AleraToastTone.success,
    );
  } catch (error) {
    AleraToast.publish(message: '$error', tone: AleraToastTone.error);
  }
}

Future<String?> _askForText(
  BuildContext context, {
  required String title,
  required String label,
  required String confirm,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 16,
            decoration: InputDecoration(labelText: label),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(confirm),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Set<String> automationPortableCatalogKeys(JsonMap bundle) {
  final result = <String>{};
  for (final item in automationJsonList(bundle['definitions'])) {
    final definition = automationJsonMap(item);
    if (automationJsonOptionalString(definition['projectKey'])
        case final key?) {
      result.add(key);
    }
    for (final details in automationJsonMap(definition['target']).values) {
      final map = automationJsonMap(details);
      for (final key in <String>[
        'workspaceKey',
        'sourceWorkspaceKey',
        'tabKey',
        'profileKey',
        'conversationKey',
      ]) {
        if (automationJsonOptionalString(map[key]) case final value?) {
          result.add(value);
        }
      }
    }
  }
  for (final item in automationJsonList(bundle['templates'])) {
    if (automationJsonOptionalString(automationJsonMap(item)['projectKey'])
        case final key?) {
      result.add(key);
    }
  }
  return result;
}
