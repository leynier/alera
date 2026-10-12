import 'dart:convert';

import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/infra/run_watch.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/foundation.dart';

/// `recipes.*`: the catalog New Run picks from and Settings > Recipes edits.
class RecipeRepository {
  RecipeRepository(this.client);
  final RuntimeHostClient client;

  Future<Map<String, Object?>> request(
    String verb,
    Map<String, Object?> payload,
  ) async {
    final capabilityClient = client;
    if (capabilityClient is! RuntimeHostCapabilityClient ||
        !await (capabilityClient as RuntimeHostCapabilityClient)
            .supportsRuntimeCapability(aleraRuntimeHostRecipesCapability)) {
      throw const RunsUpdateRequired(recipes: true);
    }
    final response = await client.runtimeRequest(
      verb,
      payload,
      const Duration(seconds: 30),
    );
    if (response is! Map) {
      throw const FormatException('Invalid recipe catalog response.');
    }
    return Map<String, Object?>.from(response);
  }

  /// Fires when a recipe was saved, exported or removed on the host, and
  /// after a reconnect, which may have missed such an event.
  Stream<void> catalogChanges() => client.runtimeEvents
      .where(
        (event) =>
            event.name == recipesChangedEvent ||
            event.name == aleraRuntimeHostConnectedEvent,
      )
      .map((_) {});

  Future<Map<String, Object?>> list(String? workspaceId) =>
      request('recipes.catalog', {'workspaceId': ?workspaceId});

  Future<Map<String, Object?>> read(Map<String, Object?> source) =>
      request('recipes.recipe', {'source': source});

  Future<Map<String, Object?>> validate(String document) =>
      request('recipes.validate', {'document': document});

  Future<Map<String, Object?>> save(String document, int? revision) => request(
    'recipes.savePersonal',
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
      expectedDigest == null ? 'recipes.previewExport' : 'recipes.applyExport',
      {
        'workspaceId': workspaceId,
        'filename': filename,
        'document': document,
        'expectedDigest': ?expectedDigest,
      },
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
