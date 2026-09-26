import 'package:alera/src/features/projects/infra/runtime_project_hosts_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'project_hosts_providers.g.dart';

@Riverpod(keepAlive: true)
RuntimeProjectHostsClient projectHostsClient(Ref ref) {
  final client = ref.watch(runtimeHostClientProvider);
  final migration = ref.watch(runtimeStateMigrationProvider);
  return RuntimeProjectHostsClient((type, payload, timeout) async {
    await migration.ensureMigrated();
    return client.runtimeRequest(type, payload, timeout);
  });
}

/// Whether the connected runtime can put one project on several hosts. An
/// unreachable runtime reads as unsupported so no control is offered that the
/// host would reject.
@riverpod
Future<bool> projectHostsSupported(Ref ref) async {
  try {
    return await ref
        .watch(runtimeHostClientProvider)
        .supportsRuntimeCapability(aleraRuntimeHostProjectHostsCapability);
  } catch (_) {
    return false;
  }
}
