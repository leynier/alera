import 'dart:convert';

import 'package:alera/src/features/orchestration/infra/workflow_catalog_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (exists, matches) in [
    (false, false),
    (true, false),
    (true, true),
  ]) {
    test(
      'personal recovery reads candidate id, exists=$exists matches=$matches',
      () async {
        final client = _Client()
          ..responses = {
            'workflows.validateRecipe': {
              'recipe': {'id': 'candidate'},
              'digest': 'draft',
            },
            'workflows.catalog': {
              'entries': [
                if (exists)
                  {
                    'source': {'origin': 'personal', 'id': 'candidate'},
                  },
              ],
            },
            'workflows.recipe': {
              'source': {'origin': 'personal', 'id': 'candidate'},
              'recipe': {'id': 'candidate'},
              'catalogRevision': 4,
              'digest': matches ? 'draft' : 'different',
            },
          };
        final result = await WorkflowCatalogRepository(client)
            .reviewPersonal('draft');
        expect(client.verbs, [
          'workflows.validateRecipe',
          'workflows.catalog',
          if (exists) 'workflows.recipe',
        ]);
        expect(result['id'], 'candidate');
        if (exists) {
          expect(client.payload, {
            'source': {'origin': 'personal', 'id': 'candidate'},
          });
          expect(result['matches'], matches);
        } else {
          expect(result['missing'], true);
        }
      },
    );
  }

  test('large portable documents fall back to compact UTF-8 JSON', () async {
    final recipe = {
      'contracts': [
        {'instructions': List.filled(131050, 'é').join()},
      ],
    };
    final compact = jsonEncode(recipe);
    final pretty = const JsonEncoder.withIndent('  ').convert(recipe);
    expect(utf8.encode(compact).length, lessThanOrEqualTo(256 * 1024));
    expect(utf8.encode(pretty).length, greaterThan(256 * 1024));
    expect(pretty.length, lessThan(256 * 1024));
    final document = await WorkflowCatalogRepository(_Client())
        .document(recipe);
    expect(document, compact);
    expect(jsonDecode(document), recipe);
  });

  test('small portable documents retain readable formatting', () async {
    const recipe = {'id': 'small'};
    expect(
      await WorkflowCatalogRepository(_Client()).document(recipe),
      const JsonEncoder.withIndent('  ').convert(recipe),
    );
  });

  test('catalog and export negotiate independent capabilities', () async {
    final client = _Client();
    final repository = WorkflowCatalogRepository(client);
    await repository.list('workspace');
    expect(client.capabilities, ['workflowRecipeCatalogV1']);
    expect(client.payload, {'workspaceId': 'workspace'});
    client.supported = false;
    await expectLater(
      repository.export(
        workspaceId: 'workspace',
        filename: 'recipe.yaml',
        document: '{}',
      ),
      throwsA(isA<WorkflowCatalogUpdateRequired>()),
    );
    expect(client.verbs, ['workflows.catalog']);
    expect(client.capabilities.last, 'workflowRecipeExportV1');
  });

  test('personal update carries its catalog revision unchanged', () async {
    final client = _Client();
    await WorkflowCatalogRepository(client).save('document', 7);
    expect(client.verbs, ['workflows.savePersonalRecipe']);
    expect(client.payload, {'document': 'document', 'expectedRevision': 7});
  });

  test('reviewed export binds digest and renders changed lines', () async {
    final client = _Client()
      ..response = {
        'before': 'same\nold\nlast',
        'after': 'same\nnew\nlast',
        'expectedDigest': 'digest',
      };
    final result = await WorkflowCatalogRepository(client).export(
      workspaceId: 'workspace',
      filename: 'recipe.yaml',
      document: '{}',
      expectedDigest: 'digest',
    );
    expect(client.verbs, ['workflows.applyRecipeExport']);
    expect(client.payload['expectedDigest'], 'digest');
    expect(result['diff'], contains('-old\n+new'));
    expect(result['diff'], isNot(contains('-same')));
  });
}

class _Client implements RuntimeHostClient, RuntimeHostCapabilityClient {
  bool supported = true;
  final capabilities = <String>[];
  final verbs = <String>[];
  Map<String, Object?> payload = {};
  Map<String, Object?> response = {};
  Map<String, Map<String, Object?>> responses = {};
  @override
  Future<bool> supportsRuntimeCapability(String capability) async {
    capabilities.add(capability);
    return supported;
  }

  @override
  Future<Object?> runtimeRequest(
    String verb, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    verbs.add(verb);
    this.payload = payload;
    return responses[verb] ?? response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
