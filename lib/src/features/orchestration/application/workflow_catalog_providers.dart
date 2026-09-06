import 'package:alera/src/features/orchestration/infra/workflow_catalog_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workflow_catalog_providers.g.dart';

@riverpod
WorkflowCatalogRepository workflowCatalogRepository(Ref ref) =>
    WorkflowCatalogRepository(ref.watch(runtimeHostClientProvider));

class WorkflowCatalogEdit {
  const WorkflowCatalogEdit(
    this.record,
    this.document,
    this.revision,
    this.workspaceId,
  );
  final Map<String, Object?> record;
  final String document;
  final int? revision;
  final String? workspaceId;
}

// One user-owned draft survives navigating between Settings sections. It is
// not keyed by execution workspace and holds no processes or subscriptions.
@Riverpod(keepAlive: true)
class WorkflowCatalogDraft extends _$WorkflowCatalogDraft {
  @override
  WorkflowCatalogEdit? build() => null;

  void retain(WorkflowCatalogEdit? draft) => state = draft;
}
