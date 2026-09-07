import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workflow_lifecycle_providers.g.dart';

@Riverpod(keepAlive: true)
WorkflowLifecycleRepository workflowLifecycleRepository(Ref ref) {
  final client = ref.watch(runtimeHostClientProvider);
  return WorkflowLifecycleRepository(client, client);
}
