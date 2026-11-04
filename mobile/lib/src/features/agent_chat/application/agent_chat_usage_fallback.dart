import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/quotas/application/agent_quota_controller.dart';
import 'package:alera_mobile/src/features/quotas/domain/quota_snapshot.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_usage_fallback.g.dart';

/// The quota readings of [hostId] the phone already fetched, or none while
/// they load or fail. New Chat never waits for them.
@riverpod
List<AgentChatUsageReading> agentChatUsageReadings(Ref ref, String hostId) {
  final state = ref.watch(agentQuotaControllerProvider(hostId)).value;
  return state == null
      ? const <AgentChatUsageReading>[]
      : agentChatUsageReadingsOf(state.snapshots);
}

List<AgentChatUsageReading> agentChatUsageReadingsOf(
  Iterable<QuotaSnapshot> snapshots,
) => <AgentChatUsageReading>[
  for (final snapshot in snapshots)
    AgentChatUsageReading(
      provider: snapshot.provider,
      fresh: snapshot.status == 'ok' || snapshot.status == 'stale',
      meters: <AgentChatUsageMeter>[
        for (final meter in <QuotaMeter>[
          ...snapshot.windows,
          ...snapshot.buckets,
        ])
          AgentChatUsageMeter(
            usedPercent: meter.usedPercent,
            resetsAt: meter.resetsAt,
          ),
      ],
    ),
];

String agentChatUsageFallbackKey(String hostId, String chatId) =>
    '$hostId/$chatId';

/// The notice of each new chat that started on another agent because the
/// default one was out of usage, by [agentChatUsageFallbackKey], until
/// dismissed.
@Riverpod(keepAlive: true)
class AgentChatUsageFallbacks extends _$AgentChatUsageFallbacks {
  @override
  Map<String, AgentChatUsageFallback> build() =>
      const <String, AgentChatUsageFallback>{};

  void record(String hostId, String chatId, AgentChatUsageFallback fallback) =>
      state = <String, AgentChatUsageFallback>{
        ...state,
        agentChatUsageFallbackKey(hostId, chatId): fallback,
      };

  void dismiss(String hostId, String chatId) {
    final key = agentChatUsageFallbackKey(hostId, chatId);
    if (!state.containsKey(key)) return;
    state = <String, AgentChatUsageFallback>{...state}..remove(key);
  }
}
