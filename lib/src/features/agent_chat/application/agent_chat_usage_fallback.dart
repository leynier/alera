import 'package:alera/src/features/agent_quota/application/agent_quota_providers.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_usage_fallback.g.dart';

/// The quota readings of [hostId] the status bar already fetched, or none
/// while they load, fail, or belong to another host. New Chat never waits
/// for them.
@riverpod
List<AgentChatUsageReading> agentChatUsageReadings(Ref ref, String hostId) {
  final state = ref.watch(agentQuotaStateProvider).value;
  if (state == null || state.hostId != hostId) {
    return const <AgentChatUsageReading>[];
  }
  return agentChatUsageReadingsOf(state.snapshots);
}

List<AgentChatUsageReading> agentChatUsageReadingsOf(
  Iterable<AgentQuotaSnapshot> snapshots,
) => <AgentChatUsageReading>[
  for (final snapshot in snapshots)
    AgentChatUsageReading(
      provider: snapshot.provider.name,
      fresh:
          snapshot.status == AgentQuotaStatus.ok ||
          snapshot.status == AgentQuotaStatus.stale,
      meters: <AgentChatUsageMeter>[
        for (final window in snapshot.windows)
          AgentChatUsageMeter(
            usedPercent: window.usedPercent,
            resetsAt: window.resetsAt,
          ),
        for (final bucket in snapshot.buckets)
          AgentChatUsageMeter(
            usedPercent: bucket.usedPercent,
            resetsAt: bucket.resetsAt,
          ),
      ],
    ),
];

/// The notice of each new chat that started on another agent because the
/// default one was out of usage, by chat id, until dismissed.
@Riverpod(keepAlive: true)
class AgentChatUsageFallbacks extends _$AgentChatUsageFallbacks {
  @override
  Map<String, AgentChatUsageFallback> build() =>
      const <String, AgentChatUsageFallback>{};

  void record(String chatId, AgentChatUsageFallback fallback) =>
      state = <String, AgentChatUsageFallback>{...state, chatId: fallback};

  void dismiss(String chatId) {
    if (!state.containsKey(chatId)) return;
    state = <String, AgentChatUsageFallback>{...state}..remove(chatId);
  }
}
