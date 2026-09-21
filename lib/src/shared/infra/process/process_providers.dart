import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/host_routed_process_runner.dart';
import 'package:alera/src/shared/infra/process/remote_process_runner.dart';
import 'package:alera/src/shared/infra/process/rust_process_runner.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'process_providers.g.dart';

@Riverpod(keepAlive: true)
ProcessRunner processRunner(Ref ref) {
  return const RustProcessRunner();
}

/// The runner for tools that act on a checkout (the forge CLIs). A working
/// directory inside a remote workspace runs the tool on that workspace's host
/// through `host.process.run`; everything else runs here. Features about this
/// machine (updater, installers, quota, keep-awake) MUST keep
/// [processRunnerProvider], which never leaves it.
@Riverpod(keepAlive: true)
ProcessRunner workspaceProcessRunner(Ref ref) {
  final remoteRunners = <String, RemoteProcessRunner>{};
  final remoteWorkspaceIdFor = ref.read(remoteWorkspacePathResolverProvider);
  return HostRoutedProcessRunner(
    local: ref.watch(processRunnerProvider),
    remoteFor: (workingDirectory) {
      final workspaceId = remoteWorkspaceIdFor(workingDirectory);
      if (workspaceId == null) {
        return null;
      }
      return remoteRunners.putIfAbsent(
        workspaceId,
        () => RemoteProcessRunner(
          ref.read(runtimeHostClientProvider),
          workspaceId: workspaceId,
          beforeAccess: ref.read(runtimeStateMigrationProvider).ensureMigrated,
        ),
      );
    },
  );
}

@Riverpod(keepAlive: true)
CommandEnvironmentResolver commandEnvironmentResolver(Ref ref) {
  return UserCommandEnvironmentResolver();
}
