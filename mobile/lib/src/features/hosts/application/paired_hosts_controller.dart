import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'paired_hosts_controller.g.dart';

@riverpod
class PairedHostsController extends _$PairedHostsController {
  @override
  Future<List<PairedHostProfile>> build() {
    return ref.watch(hostRepositoryProvider).loadHosts();
  }

  Future<void> savePairedHost(
    PairedHostProfile host,
    String deviceToken,
  ) async {
    await ref.read(hostRepositoryProvider).savePairedHost(host, deviceToken);
    ref.invalidateSelf();
    await future;
  }

  Future<void> removeHost(String hostId) async {
    await ref.read(hostRepositoryProvider).removeHost(hostId);
    ref.invalidateSelf();
    await future;
  }

  Future<void> updateHostAlias(String hostId, String? alias) async {
    final normalized = alias?.trim();
    await ref
        .read(hostRepositoryProvider)
        .updateHostAlias(
          hostId,
          normalized == null || normalized.isEmpty ? null : normalized,
        );
    ref.invalidateSelf();
    await future;
  }
}

@riverpod
Future<List<PairedHostProfile>> availableHosts(Ref ref) async {
  final logger = Logger('AvailableHosts');
  final paired = await ref.watch(pairedHostsControllerProvider.future);
  final byRuntime = <String, PairedHostProfile>{
    for (final host in paired) host.runtimeId: host,
  };
  final sessions = switch (ref.watch(cloudAccountsControllerProvider)) {
    AsyncData(value: final value) => value,
    _ => null,
  };
  if (sessions == null || sessions.isEmpty) {
    return byRuntime.values.toList(growable: false);
  }
  final api = ref.watch(aleraRelayCloudApiProvider);
  for (final session in sessions) {
    try {
      final runtimes = await api.discoverRuntimes(session);
      for (final runtime in runtimes) {
        final pairedHost = byRuntime[runtime.id];
        byRuntime[runtime.id] = pairedHost == null
            ? PairedHostProfile.fromCloudRuntime(session.account.id, runtime)
            : pairedHost.withCloudAccount(session.account.id);
      }
    } on Object catch (error, stackTrace) {
      logger.warning(
        'could not discover remote runtimes for ${session.account.id}',
        error,
        stackTrace,
      );
    }
  }
  return byRuntime.values.toList(growable: false);
}
