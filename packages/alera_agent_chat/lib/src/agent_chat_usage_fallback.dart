import 'package:alera_agent_chat/src/agent_chat_provider_catalog.dart';
import 'package:alera_agent_chat/src/agent_chat_selection.dart';

/// One usage meter of a provider account: a rate-limit window or a bucket.
final class const AgentChatUsageMeter({
  required final double usedPercent,
  final DateTime? resetsAt,
});

/// One account's usage as the app's quota snapshots report it. [provider] is
/// the quota provider id (`claude`, `codex`, `cursor`, ...). Only a [fresh]
/// reading counts: a failed or unavailable one says nothing about usage.
final class const AgentChatUsageReading({
  required final String provider,
  required final List<AgentChatUsageMeter> meters,
  final bool fresh = true,
});

/// A provider out of usage, until [resetsAt] when that is known.
final class const AgentChatUsageLimit({final DateTime? resetsAt});

/// A new chat started on [selection] because the default agent, [fromLabel],
/// was out of usage; [toLabel] names the agent it uses instead.
/// [defaultSelection] is the agent and model the chat would have started on,
/// which "Use [defaultLabel]" switches the chat back to.
final class const AgentChatUsageFallback({
  required final AgentChatSelection selection,
  required final String fromLabel,
  required final String toLabel,
  final DateTime? resetsAt,
  final AgentChatSelection? defaultSelection,
  final String? defaultLabel,
}) {
  String get title => 'Using $toLabel';

  String get detail => '$fromLabel is out of usage';

  /// "Use GPT-5.5", the action that switches back to [defaultSelection].
  String get useDefaultLabel => 'Use ${defaultLabel ?? fromLabel}';
}

/// The quota provider id for a chat provider kind; the chat's Claude agent
/// reports its quota as `claude`.
String agentChatQuotaProvider(String chatProvider) =>
    chatProvider == 'claudeAgent' ? 'claude' : chatProvider;

/// Whether [provider] (a chat provider kind) is out of usage at [now]: every
/// fresh account has a meter at or past 100% that has not reset yet. A
/// provider with no fresh reading is never out of usage, so missing quota
/// data never moves a chat. The limit resets when the first account is back.
AgentChatUsageLimit? agentChatUsageLimit(
  Iterable<AgentChatUsageReading> readings,
  String provider, {
  required DateTime now,
}) {
  final quotaProvider = agentChatQuotaProvider(provider);
  final accounts = <AgentChatUsageReading>[
    for (final reading in readings)
      if (reading.fresh &&
          reading.provider == quotaProvider &&
          reading.meters.isNotEmpty)
        reading,
  ];
  if (accounts.isEmpty) return null;
  DateTime? soonest;
  for (final account in accounts) {
    final exhausted = <AgentChatUsageMeter>[
      for (final meter in account.meters)
        if (meter.usedPercent >= 100 &&
            (meter.resetsAt == null || meter.resetsAt!.isAfter(now)))
          meter,
    ];
    if (exhausted.isEmpty) return null;
    // An account is back once every exhausted meter has reset.
    DateTime? back;
    for (final meter in exhausted) {
      final reset = meter.resetsAt;
      if (reset == null) {
        back = null;
        break;
      }
      if (back == null || reset.isAfter(back)) back = reset;
    }
    if (back != null && (soonest == null || back.isBefore(soonest))) {
      soonest = back;
    }
  }
  return AgentChatUsageLimit(resetsAt: soonest);
}

/// The agent a new chat uses instead of [resolved] when [resolved] is the
/// default (not one of [explicit]) and its provider is out of usage: the
/// first other enabled, available agent in [providers] order whose provider
/// still has usage, on its default model. Null keeps [resolved].
AgentChatUsageFallback? agentChatUsageFallback({
  required AgentChatSelection resolved,
  required List<AgentChatProviderInstance> providers,
  required AgentChatUsageLimit? Function(String provider) limitOf,
  Iterable<AgentChatSelection?> explicit = const <AgentChatSelection?>[],
}) {
  if (explicit.any(
    (selection) => selection?.providerInstanceId == resolved.providerInstanceId,
  )) {
    return null;
  }
  final from = providers
      .where((instance) => instance.id == resolved.providerInstanceId)
      .firstOrNull;
  if (from == null) return null;
  final limit = limitOf(from.provider);
  if (limit == null) return null;
  for (final instance in providers) {
    if (instance.id == from.id ||
        !instance.enabled ||
        !instance.available ||
        instance.provider == from.provider ||
        limitOf(instance.provider) != null) {
      continue;
    }
    return AgentChatUsageFallback(
      selection: AgentChatSelection(providerInstanceId: instance.id),
      fromLabel: from.label,
      toLabel: instance.label,
      resetsAt: limit.resetsAt,
      defaultSelection: resolved,
      defaultLabel: resolved.model == null
          ? from.label
          : from.modelById(resolved.model)?.label ?? resolved.model,
    );
  }
  return null;
}
