import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
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
