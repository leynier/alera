// The package's orchestration AgentChatRequestIds is a different concept.
import 'package:alera_agent_chat/alera_agent_chat.dart'
    hide AgentChatRequestIds;
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_request_ids.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

/// `Ref.read` and `WidgetRef.read` alike.
typedef AgentChatProviderReader = T Function<T>(ProviderListenable<T> provider);

/// What New Chat did.
sealed class AgentChatLaunchOutcome {
  const AgentChatLaunchOutcome();
}

/// A chat to show: a new one, or an empty one already waiting in the
/// workspace. [tabId] is absent only on a runtime that keeps no tab for it.
final class const AgentChatLaunchOpened({
  required final String chatId,
  required final String? tabId,
  final bool reused = false,
}) extends AgentChatLaunchOutcome;

/// Nothing can start a chat: no agent is enabled on the host, and the runtime
/// cannot keep a chat that has no agent yet.
final class const AgentChatLaunchNoAgent() extends AgentChatLaunchOutcome;

/// How many existing chats New Chat inspects for one it can reuse. Each costs
/// a snapshot read, and an empty chat is almost always the newest one.
const int _reuseCandidates = 3;

/// Opens a chat at once with the resolved default agent and model, the same
/// rules the desktop applies. There is no picker before the chat exists: the
/// agent and model change from the composer.
class AgentChatLauncher({
  required final String _hostId,
  required final AgentChatRepository _repository,
  required final AgentChatDraftStore _drafts,
  required final AgentChatRequestIds _requestIds,
  required final Future<List<AgentChatProviderInstance>> _providers,
  required final Future<AgentChatPreferences?> _preferences,
  required final Future<bool> _unselectedSupported,
}) {
  Future<AgentChatLaunchOutcome> open({
    required String workspaceId,
    String? projectId,
    AgentChatSelection? launchingSelection,
    String? launchingWorkspaceId,
  }) async {
    final reused = await _reusable(workspaceId);
    if (reused != null) {
      return AgentChatLaunchOpened(
        chatId: reused.chatId,
        tabId: reused.tabId,
        reused: true,
      );
    }
    final providers = await _providers;
    // Preferences only refine the default; a host that cannot read them
    // still opens a chat with the catalog's own default.
    final preferences =
        await _preferences.then<AgentChatPreferences?>(
          (preferences) => preferences,
          onError: (Object _) => null,
        ) ??
        const AgentChatPreferences();
    final selection = agentChatLaunchSelection(
      providers: providers,
      preferences: preferences,
      projectId: projectId,
      workspaceId: workspaceId,
      launchingSelection: launchingSelection,
      launchingWorkspaceId: launchingWorkspaceId,
    );
    final unselected =
        selection == null &&
        await _unselectedSupported.then(
          (supported) => supported,
          onError: (Object _) => false,
        );
    if (selection == null && !unselected) return const AgentChatLaunchNoAgent();
    final requestId = _requestIds.claimCreate(_hostId, workspaceId);
    try {
      final result = await _repository.create(
        selection?.createInput(
              requestId: requestId,
              workspaceId: workspaceId,
            ) ??
            AgentChatCreateInput(
              requestId: requestId,
              workspaceId: workspaceId,
            ),
      );
      _requestIds.settleCreate(_hostId, workspaceId);
      _drafts.activate(_hostId, result.chatId);
      return AgentChatLaunchOpened(chatId: result.chatId, tabId: result.tabId);
    } on AgentChatConnectionException {
      // The create may have landed; the next press replays its receipt.
      rethrow;
    } on Object {
      _requestIds.settleCreate(_hostId, workspaceId);
      rethrow;
    }
  }

  /// An open chat nobody has written to yet, whose draft here is empty. It
  /// only gets focused: another device may be typing into it, and nothing is
  /// deleted or rewritten either way.
  Future<AgentChatSummary?> _reusable(String workspaceId) async {
    final chats = await _repository.list(workspaceId: workspaceId);
    final candidates = <AgentChatSummary>[
      for (final chat in chats)
        if (!chat.archived &&
            chat.tabId != null &&
            !chat.busy &&
            chat.pendingRequestCount == 0 &&
            _drafts.read(_hostId, chat.chatId).isEmpty)
          chat,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final chat in candidates.take(_reuseCandidates)) {
      final snapshot = await _repository.snapshot(
        AgentChatRef(chatId: chat.chatId, workspaceId: chat.workspaceId),
      );
      if (snapshot.neverSent &&
          snapshot.queue.isEmpty &&
          snapshot.pendingNativeOperation == null) {
        return chat;
      }
    }
    return null;
  }
}

/// The agent a new chat starts with. An available choice wins by the shared
/// precedence; failing that, a preference whose agent is enabled but not
/// ready still names the chat's agent, which then explains why it cannot
/// start. Only with no enabled agent at all is there no selection.
AgentChatSelection? agentChatLaunchSelection({
  required List<AgentChatProviderInstance> providers,
  required AgentChatPreferences preferences,
  String? projectId,
  String? workspaceId,
  AgentChatSelection? launchingSelection,
  String? launchingWorkspaceId,
}) {
  final resolved = preferences.resolve(
    providers: providers,
    projectId: projectId,
    launchingSelection: launchingSelection,
    workspaceId: workspaceId,
    launchingWorkspaceId: launchingWorkspaceId,
  );
  if (resolved != null) return resolved;
  final enabled = <String>{
    for (final instance in providers)
      if (instance.enabled) instance.id,
  };
  for (final preferred in <AgentChatSelection?>[
    if (projectId != null) preferences.projectDefaults[projectId],
    if (workspaceId != null && workspaceId == launchingWorkspaceId)
      launchingSelection,
    preferences.defaultSelection,
    preferences.rememberedSelection,
  ]) {
    if (preferred != null && enabled.contains(preferred.providerInstanceId)) {
      return preferred;
    }
  }
  for (final instance in providers) {
    if (instance.enabled) {
      return AgentChatSelection(providerInstanceId: instance.id);
    }
  }
  return null;
}

/// Builds a launcher for one New Chat press. Everything it reads is asked
/// for up front, so leaving the screen while it works cannot strand a read on
/// a disposed ref; the answers that end up unused are simply dropped.
Future<AgentChatLauncher> agentChatLauncherFor(
  AgentChatProviderReader read, {
  required String hostId,
  required String workspaceId,
  String? remoteHostId,
}) async {
  final providers = read(agentChatProvidersProvider(hostId, workspaceId).future)
    ..ignore();
  final preferences = read(
    agentChatPreferencesProvider(hostId, remoteHostId).future,
  )..ignore();
  final unselected = read(
    agentChatCapabilityProvider(
      hostId,
      AgentChatWire.unselectedDraftCapability,
    ).future,
  )..ignore();
  return AgentChatLauncher(
    hostId: hostId,
    repository: await read(agentChatRepositoryProvider(hostId).future),
    drafts: read(agentChatDraftStoreProvider),
    requestIds: read(agentChatRequestIdsProvider),
    providers: providers,
    preferences: preferences,
    unselectedSupported: unselected,
  );
}
