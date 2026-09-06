import 'package:alera/src/features/orchestration/infra/workflow_catalog_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
