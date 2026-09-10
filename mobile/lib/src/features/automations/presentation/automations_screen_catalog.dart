import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

Set<String> portableAutomationCatalogKeys(Map<String, Object?> bundle) {
  final result = <String>{};
  final definitions = bundle['definitions'];
  if (definitions is List) {
    for (final item in definitions.whereType<Map>()) {
      final definition = <String, Object?>{
        for (final entry in item.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      if (definition['projectKey'] is String) {
        result.add(definition['projectKey']! as String);
      }
      final target = definition['target'];
      if (target is! Map) continue;
      for (final details in target.values.whereType<Map>()) {
        for (final key in <String>[
          'workspaceKey',
          'sourceWorkspaceKey',
          'tabKey',
          'profileKey',
          'conversationKey',
        ]) {
          final value = details[key];
          if (value is String && value.trim().isNotEmpty) result.add(value);
        }
      }
    }
  }
  final templates = bundle['templates'];
  if (templates is List) {
    for (final item in templates.whereType<Map>()) {
      final projectKey = item['projectKey'];
      if (projectKey is String && projectKey.trim().isNotEmpty) {
        result.add(projectKey.trim());
      }
    }
  }
  return result;
}

class const AutomationsEmptyState({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: AleraTokens.pagePadding,
      child: Text('No automations are configured on this host.'),
    ),
  );
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
            : error.toString(),
        textAlign: .center,
      ),
    ),
  );
}
