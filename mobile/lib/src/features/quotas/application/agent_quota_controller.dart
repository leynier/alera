import 'dart:async';

import 'package:alera_mobile/src/features/quotas/domain/quota_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_quota_controller.g.dart';

const Duration mobileQuotaRefreshInterval = Duration(minutes: 5);

@riverpod
class AgentQuotaController extends _$AgentQuotaController {
  @override
  Future<QuotaSnapshotState> build(String hostId) async {
    final client = await ref.watch(
      hostConnectionControllerProvider(hostId).future,
    );
    if (!client.supportsAgentQuotas) {
      throw UnsupportedError('Update The Runtime To View Quotas.');
    }
    final timer = Timer(mobileQuotaRefreshInterval, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
    return client.fetchAgentQuotas();
  }

  Future<void> refresh() async {
    final client = await ref.read(
      hostConnectionControllerProvider(hostId).future,
    );
    state = const AsyncLoading<QuotaSnapshotState>();
    state = await AsyncValue.guard(
      () => client.fetchAgentQuotas(forceRefresh: true),
    );
  }
}
