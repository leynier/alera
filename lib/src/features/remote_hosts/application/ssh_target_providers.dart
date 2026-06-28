import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/infra/runtime_ssh_target_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ssh_target_providers.g.dart';

@Riverpod(keepAlive: true)
RuntimeSshTargetRepository sshTargetRepository(Ref ref) {
  return RuntimeSshTargetRepository(ref.watch(runtimeHostClientProvider));
}

@Riverpod(keepAlive: true)
Stream<List<SshTarget>> sshTargets(Ref ref) {
  return ref.watch(sshTargetRepositoryProvider).watchAll();
}

@Riverpod(keepAlive: true)
Stream<SshTargetBootstrapProgress> sshTargetBootstrapProgress(Ref ref) {
  return ref.watch(sshTargetRepositoryProvider).watchBootstrapProgress();
}
