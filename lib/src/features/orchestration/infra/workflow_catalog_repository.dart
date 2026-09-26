import 'dart:convert';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/foundation.dart';

class WorkflowCatalogUpdateRequired implements Exception {
  const WorkflowCatalogUpdateRequired();
  @override
  String toString() => 'Update the runtime to manage workflow recipes.';
}

class WorkflowCatalogRepository {
  WorkflowCatalogRepository(this.client);
  final RuntimeHostClient client;

  Future<Map<String, Object?>> request(
    String verb,
    Map<String, Object?> payload, {
    bool export = false,
  }) async {
    final capabilityClient = client;
    if (capabilityClient is! RuntimeHostCapabilityClient ||
        !await (capabilityClient as RuntimeHostCapabilityClient)
            .supportsRuntimeCapability(
              export ? 'workflowRecipeExportV1' : 'workflowRecipeCatalogV1',
            )) {
      throw const WorkflowCatalogUpdateRequired();
    }
    final response = await client.runtimeRequest(
      verb,
      payload,
      const Duration(seconds: 30),
    );
    if (response is! Map) {
      throw const FormatException('Invalid workflow catalog response.');
    }
    return Map<String, Object?>.from(response);
  }

  Future<Map<String, Object?>> list(String? workspaceId) =>
      request('workflows.catalog', {'workspaceId': ?workspaceId});

  Future<Map<String, Object?>> read(Map<String, Object?> source) =>
      request('workflows.recipe', {'source': source});

  Future<Map<String, Object?>> validate(String document) =>
      request('workflows.validateRecipe', {'document': document});

  Future<Map<String, Object?>> save(String document, int? revision) => request(
    'workflows.savePersonalRecipe',
    {'document': document, 'expectedRevision': ?revision},
  );

  Future<Map<String, Object?>> reviewPersonal(String draft) async {
    final validated = await validate(draft);
    final id = (validated['recipe']! as Map)['id']! as String;
    final catalog = await list(null);
    final exists = (catalog['entries']! as List).any((entry) {
      final source = (entry as Map)['source']! as Map;
      return source['origin'] == 'personal' && source['id'] == id;
    });
    if (!exists) return {'id': id, 'missing': true};
    final record = await read({'origin': 'personal', 'id': id});
    final current = await document(record['recipe']);
    final proposed = await document(validated['recipe']);
    return {
      'id': id,
      'record': record,
      'document': current,
      'matches':
          record['digest'] is String && record['digest'] == validated['digest'],
      'diff': await compute(_exportDiff, {
        'before': current,
        'after': proposed,
      }),
    };
  }

  Future<Map<String, Object?>> export({
    required String workspaceId,
    required String filename,
    required String document,
    String? expectedDigest,
  }) async {
    final response = await request(
      expectedDigest == null
          ? 'workflows.previewRecipeExport'
          : 'workflows.applyRecipeExport',
      {
        'workspaceId': workspaceId,
        'filename': filename,
        'document': document,
        'expectedDigest': ?expectedDigest,
      },
      export: true,
    );
    response['diff'] = await compute(_exportDiff, response);
    return response;
  }

  // Documents may contain bounded but large schemas; keep encoding off the UI isolate.
  Future<String> document(Object? recipe) => compute(_encodeDocument, recipe);
}

String _encodeDocument(Object? recipe) {
  final pretty = const JsonEncoder.withIndent('  ').convert(recipe);
  // Match the runtime's portable document limit, including multibyte text.
  return utf8.encode(pretty).length <= 256 * 1024 ? pretty : jsonEncode(recipe);
}

String _exportDiff(Map<String, Object?> preview) {
  final before = (preview['before'] as String?)?.split('\n') ?? <String>[];
  final after = (preview['after']! as String).split('\n');
  var prefix = 0;
  while (prefix < before.length &&
      prefix < after.length &&
      before[prefix] == after[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < before.length - prefix &&
      suffix < after.length - prefix &&
      before[before.length - suffix - 1] == after[after.length - suffix - 1]) {
    suffix++;
  }
  if (prefix == before.length && prefix == after.length) return 'No changes.';
  return [
    '--- Current',
    '+++ Export',
    '@@ -${prefix + 1},${before.length - prefix - suffix} +${prefix + 1},${after.length - prefix - suffix} @@',
    ...before.sublist(prefix, before.length - suffix).map((line) => '-$line'),
    ...after.sublist(prefix, after.length - suffix).map((line) => '+$line'),
  ].join('\n');
}
