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

  Future<void> tryClaudeWithTui(QuotaSnapshot snapshot) async {
    final client = await ref.read(
      hostConnectionControllerProvider(hostId).future,
    );
    if (!client.supportsAgentQuotaClaudeTui) {
      throw UnsupportedError('Update The Runtime To Try Claude With TUI.');
    }
    final updated = await client.fetchClaudeQuotaViaTui(
      accountId: snapshot.accountId,
      displayName: snapshot.displayName,
    );
    final previous = state.value;
    if (previous == null) {
      ref.invalidateSelf();
      return;
    }
    final snapshots = <QuotaSnapshot>[
      for (final item in previous.snapshots)
        if (item.provider == updated.provider &&
            item.accountId == updated.accountId)
          updated
        else
          item,
    ];
    if (!snapshots.any(
      (item) =>
          item.provider == updated.provider &&
          item.accountId == updated.accountId,
    )) {
      snapshots.add(updated);
    }
    state = AsyncData(
      QuotaSnapshotState(
        snapshots: snapshots,
        environment: previous.environment,
        fetchedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<CodexResetConsumeResult> consumeCodexResetCredit(
    QuotaSnapshot snapshot,
  ) async {
    final credits = snapshot.rateLimitResetCredits;
    if (credits == null || !credits.canConsume) {
      throw StateError('No Codex Reset Credit Is Available.');
    }
    final client = await ref.read(
      hostConnectionControllerProvider(hostId).future,
    );
    if (!client.supportsCodexResetCredits) {
      throw UnsupportedError('Update The Runtime To Use Codex Resets.');
    }
    final result = await client.consumeCodexResetCredit(credits.offerRevision);
    final previous = state.value;
    if (previous == null) {
      ref.invalidateSelf();
      return result;
    }
    final snapshots = <QuotaSnapshot>[
      for (final item in previous.snapshots)
        if (item.provider == result.snapshot.provider &&
            item.accountId == result.snapshot.accountId)
          result.snapshot
        else
          item,
    ];
    state = AsyncData(
      QuotaSnapshotState(
        snapshots: snapshots,
        environment: previous.environment,
        fetchedAt: DateTime.now().toUtc(),
      ),
    );
    return result;
  }
}
