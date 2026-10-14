import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';

/// Where the runtime's agent catalog is for the composer.
enum AgentChatCatalogState { loading, failed, ready }

/// What a chat's model reads as: the catalog's label for [modelId], else the
/// raw id, else the provider-default row, since a chat without a model runs
/// whatever its agent defaults to and the actual model is not known here.
String agentChatModelLabel(
  AgentChatProviderInstance? instance,
  String? modelId,
) =>
    instance?.modelById(modelId)?.label ??
    modelId ??
    agentChatProviderDefaultLabel;

/// The settings the composer shows for the chat's next turn.
final class const AgentChatComposerSettings({
  required final String provider,
  required final String providerInstanceId,
  required final AgentChatSession session,
  required final List<AgentChatProviderInstance> providers,
  required final bool canSwitchProvider,
  required final bool configuring,
  final AgentChatCatalogState catalog = AgentChatCatalogState.ready,
  final bool neverSent = false,
  final String? switchBlockedReason,
  final AgentChatPreferences preferences = const AgentChatPreferences(),
  final AgentChatPendingModel? pendingModel,
}) {
  /// Whether the chat has an agent; an unselected draft has none yet.
  bool get hasSelection => providerInstanceId.isNotEmpty || provider.isNotEmpty;

  AgentChatProviderInstance? get instance {
    for (final candidate in providers) {
      if (candidate.id == providerInstanceId) return candidate;
    }
    return null;
  }

  String get providerLabel => hasSelection
      ? instance?.label ?? agentChatProviderFallbackLabel(provider)
      : agentChatNoAgentLabel;

  AgentChatModelOption? get model => instance?.modelById(session.model);

  /// The model the chat runs, naming the provider default explicitly when
  /// no model was chosen; a chat without an agent names that instead.
  String get modelLabel => hasSelection
      ? agentChatModelLabel(instance, session.model)
      : providerLabel;

  /// What the picker chip reads: a held pick first, since that is what the
  /// next message uses.
  String get chipLabel => pendingModel?.label ?? modelLabel;

  AgentChatSelection get currentSelection => AgentChatSelection(
    providerInstanceId: providerInstanceId.isEmpty
        ? provider
        : providerInstanceId,
    model: session.model,
  );

  /// The reasoning efforts the current model offers; empty hides the chip.
  List<String> get reasoningEfforts =>
      model?.reasoningEfforts ?? const <String>[];

  String? get reasoningEffort =>
      session.reasoningEffort ?? model?.defaultReasoningEffort;

  /// The agent is known on this runtime but cannot start right now.
  bool get providerUnavailable {
    final current = instance;
    return current != null && (!current.available || !current.enabled);
  }
}
