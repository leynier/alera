import 'package:alera/src/features/orchestration/domain/run_execution_policy.dart';
import 'package:alera/src/features/orchestration/infra/runtime_run_policy_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'run_policy_providers.g.dart';

@Riverpod(keepAlive: true)
RuntimeRunPolicyRepository runPolicyRepository(Ref ref) {
  return RuntimeRunPolicyRepository(ref.watch(runtimeHostClientProvider));
}

/// Plans the user can review. Fetched on demand rather than watched: runs are
/// not a live surface in the app, and a plan only changes when someone acts.
@riverpod
Future<List<RunExecutionPolicy>> runExecutionPolicies(Ref ref) {
  return ref.watch(runPolicyRepositoryProvider).listPolicies();
}
