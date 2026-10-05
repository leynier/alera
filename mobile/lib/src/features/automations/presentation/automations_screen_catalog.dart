import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_json_fields.dart';
import 'package:alera_mobile/src/features/automations/presentation/authoring/mobile_automation_authoring_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

enum _CatalogAction { template, import, export }

/// Templates, import and export, kept in the overflow menu.
class const AutomationsCatalogMenu({required final String hostId, super.key})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_CatalogAction>(
      tooltip: 'More Actions',
      icon: const Icon(AleraIcons.more),
      onSelected: (action) => unawaited(switch (action) {
        _CatalogAction.template => _useTemplate(context, ref, hostId),
        _CatalogAction.import => _import(context, ref, hostId),
        _CatalogAction.export => _export(context, ref, hostId),
      }),
      itemBuilder: (_) => const <PopupMenuEntry<_CatalogAction>>[
        PopupMenuItem(
          value: _CatalogAction.template,
          height: AleraTokens.minTapTarget,
          child: Text('New From Template'),
        ),
        PopupMenuItem(
          value: _CatalogAction.import,
          height: AleraTokens.minTapTarget,
          child: Text('Import Automations'),
        ),
        PopupMenuItem(
          value: _CatalogAction.export,
          height: AleraTokens.minTapTarget,
          child: Text('Share Catalog As JSON'),
        ),
      ],
    );
  }
}

void _message(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? AleraTokens.error : null,
    ),
  );
}

Future<void> _useTemplate(
  BuildContext context,
  WidgetRef ref,
  String hostId,
) async {
  try {
    final repository = await ref.read(
      mobileAutomationRepositoryProvider(hostId).future,
    );
    final templates = await repository.templates();
    if (!context.mounted) return;
    final selected = await showModalBottomSheet<JsonMap>(
      context: context,
      builder: (sheetContext) => templates.isEmpty
          ? const Padding(
              padding: AleraTokens.pagePadding,
              child: Text(
                'No templates are saved. Save an automation as a template on the desktop first.',
              ),
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
                    onTap: () => Navigator.of(sheetContext).pop(template),
                  ),
              ],
            ),
    );
    if (selected == null || !context.mounted) return;
    await showMobileAutomationAuthoring(
      context,
      hostId: hostId,
      template: selected,
    );
  } on Object catch (error) {
    if (context.mounted) _message(context, '$error', error: true);
  }
}

Future<void> _export(BuildContext context, WidgetRef ref, String hostId) async {
  try {
    final repository = await ref.read(
      mobileAutomationRepositoryProvider(hostId).future,
    );
    final bundle = await repository.exportCatalog();
    await SharePlus.instance.share(ShareParams(text: jsonEncode(bundle)));
  } on Object catch (error) {
    if (context.mounted) _message(context, '$error', error: true);
  }
}

Future<void> _import(BuildContext context, WidgetRef ref, String hostId) async {
  final text = await _askForText(
    context,
    title: 'Import Automations',
    label: 'Versioned JSON Catalog',
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('The catalog JSON must be an object.');
    }
    final bundle = automationJsonMap(decoded);
    final keys = portableAutomationCatalogKeys(bundle).toList()..sort();
    var remap = const <String, String>{};
    if (keys.isNotEmpty) {
      if (!context.mounted) return;
      final mapping = await _askForText(
        context,
        title: 'Map Imported Targets',
        label: 'Source Key To Local Id JSON',
        initial: jsonEncode(<String, String>{for (final key in keys) key: ''}),
      );
      if (mapping == null) return;
      final value = jsonDecode(mapping);
      if (value is! Map) {
        throw const FormatException('The mapping must be a JSON object.');
      }
      remap = <String, String>{
        for (final entry in value.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: (entry.value as String).trim(),
      };
    }
    final repository = await ref.read(
      mobileAutomationRepositoryProvider(hostId).future,
    );
    await repository.importCatalog(bundle, remap);
    ref.invalidate(mobileAutomationCatalogProvider(hostId));
    if (context.mounted) {
      _message(
        context,
        'Automation catalog imported. Imported automations arrive as drafts; activate them when ready.',
      );
    }
  } on Object catch (error) {
    if (context.mounted) _message(context, '$error', error: true);
  }
}

Future<String?> _askForText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          minLines: 8,
          maxLines: 15,
          decoration: InputDecoration(labelText: label),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Set<String> portableAutomationCatalogKeys(Map<String, Object?> bundle) {
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

class const AutomationsErrorState({required final Object error, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AleraTokens.pagePadding,
      child: Text(
        error is UnsupportedError
            ? 'Update the runtime to manage automations from mobile.'
            : 'Automations are unavailable: $error',
        textAlign: .center,
      ),
    ),
  );
}
