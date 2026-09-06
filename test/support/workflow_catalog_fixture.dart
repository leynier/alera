import 'dart:async';

import 'package:alera/src/features/orchestration/infra/workflow_catalog_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

const workflowCatalogRecord = <String, Object?>{
  'source': {'origin': 'personal', 'id': 'feature-delivery'},
  'catalogRevision': 3,
  'recipe': {
    'id': 'feature-delivery',
    'revision': 1,
    'name': 'Feature Delivery',
    'description': 'Build a reviewed foundation, deliver the change, then validate the product.',
    'stages': [
      {
        'name': 'Foundation',
        'purpose': 'Review the design and implementation plan.',
        'gate': 'foundation',
      },
      {'name': 'Implementation', 'purpose': 'Build and verify isolated tasks.'},
      {
        'name': 'Product',
        'purpose': 'Review the integrated result.',
        'gate': 'product',
      },
    ],
    'contracts': [
      {
        'id': 'builder',
        'revision': 1,
        'purpose': 'Implement the approved change.',
        'instructions':
            'Preserve unrelated work and report validation evidence.',
      },
    ],
  },
};

class CatalogTestRepository extends WorkflowCatalogRepository {
  CatalogTestRepository() : super(_UnusedClient());
  Object? failure;
  int saves = 0;
  String? validatedId;
  Completer<Map<String, Object?>>? pendingSave;
  @override
  Future<Map<String, Object?>> list(String? workspaceId) async {
    if (failure != null) throw failure!;
    return {
      'entries': [
        {'source': workflowCatalogRecord['source'], 'name': 'Feature Delivery'},
      ],
    };
  }

  @override
  Future<Map<String, Object?>> read(Map<String, Object?> source) async =>
      workflowCatalogRecord;
  @override
  Future<String> document(Object? recipe) async => 'portable document';
  @override
  Future<Map<String, Object?>> validate(String document) async => {
    'recipe': {'id': validatedId ?? 'feature-delivery'},
  };
  @override
  Future<Map<String, Object?>> save(String document, int? revision) async {
    saves++;
    if (pendingSave != null) return pendingSave!.future;
    if (failure != null) throw failure!;
    return workflowCatalogRecord;
  }
}

class _UnusedClient implements RuntimeHostClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
