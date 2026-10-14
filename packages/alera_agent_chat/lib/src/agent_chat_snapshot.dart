import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_native_operation.dart';
import 'package:alera_agent_chat/src/agent_chat_queue_entry.dart';
import 'package:alera_agent_chat/src/agent_chat_request.dart';
import 'package:alera_agent_chat/src/agent_chat_session.dart';
import 'package:alera_agent_chat/src/agent_chat_title_source.dart';

/// `agentChat.snapshot`: the runtime's projection of one chat at [cursor].
/// Every later `agentChatChanged` for the chat carries the next cursor.
class const AgentChatSnapshot({
  required final String chatId,
  required final String workspaceId,
  required final int cursor,
  final String? tabId,
  final String provider = '',
  final String providerInstanceId = '',
  final String title = '',
  final AgentChatTitleSource titleSource = AgentChatTitleSource.defaultLabel,
  final bool archived = false,
  final AgentChatSession session = const AgentChatSession(),
  final List<AgentChatTurn> turns = const <AgentChatTurn>[],
  final List<AgentChatItem> items = const <AgentChatItem>[],
  final List<AgentChatRequest> pendingRequests = const <AgentChatRequest>[],
  final List<AgentChatQueueEntry> queue = const <AgentChatQueueEntry>[],
  final AgentChatUsage usage = const AgentChatUsage(),
  final AgentChatRecovery? recovery,
  final AgentChatNativeOperation? pendingNativeOperation,
  final String? historyBefore,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    final chatId = agentChatJsonString(json['chatId']);
    if (chatId == null) {
      throw const FormatException('Agent chat snapshot has no chatId.');
    }
    final recovery = json['recovery'];
    return AgentChatSnapshot(
      chatId: chatId,
      workspaceId: agentChatJsonText(json['workspaceId']),
      cursor: agentChatJsonInt(json['cursor']) ?? 0,
      tabId: agentChatJsonString(json['tabId']),
      provider: agentChatJsonText(json['provider']),
      providerInstanceId: agentChatJsonText(json['providerInstanceId']),
      title: agentChatJsonText(json['title']),
      titleSource: AgentChatTitleSource.fromJson(json['titleSource']),
      archived: agentChatJsonBool(json['archived']),
      session: AgentChatSession.fromJson(json['session']),
      turns: agentChatTurnsFromJson(json['turns']),
      items: agentChatItemsFromJson(json['items']),
      pendingRequests: agentChatRequestsFromJson(json['pendingRequests']),
      queue: agentChatQueueFromJson(json['queue']),
      usage: AgentChatUsage.fromJson(json['usage']),
      recovery: recovery is Map ? AgentChatRecovery.fromJson(recovery) : null,
      pendingNativeOperation: agentChatPendingNativeOperationFromJson(
        json['pendingNativeOperation'],
      ),
      historyBefore: agentChatJsonString(json['historyBefore']),
    );
  }

  AgentChatSnapshot copyWith({
    String? workspaceId,
    int? cursor,
    String? provider,
    String? providerInstanceId,
    String? title,
    AgentChatTitleSource? titleSource,
    bool? archived,
    AgentChatSession? session,
    List<AgentChatTurn>? turns,
    List<AgentChatItem>? items,
    List<AgentChatRequest>? pendingRequests,
    List<AgentChatQueueEntry>? queue,
    AgentChatUsage? usage,
    Object? recovery = _unchanged,
    Object? pendingNativeOperation = _unchanged,
    Object? historyBefore = _unchanged,
  }) => AgentChatSnapshot(
    chatId: chatId,
    workspaceId: workspaceId ?? this.workspaceId,
    cursor: cursor ?? this.cursor,
    tabId: tabId,
    provider: provider ?? this.provider,
    providerInstanceId: providerInstanceId ?? this.providerInstanceId,
    title: title ?? this.title,
    titleSource: titleSource ?? this.titleSource,
    archived: archived ?? this.archived,
    session: session ?? this.session,
    turns: turns ?? this.turns,
    items: items ?? this.items,
    pendingRequests: pendingRequests ?? this.pendingRequests,
    queue: queue ?? this.queue,
    usage: usage ?? this.usage,
    recovery: identical(recovery, _unchanged)
        ? this.recovery
        : recovery as AgentChatRecovery?,
    pendingNativeOperation: identical(pendingNativeOperation, _unchanged)
        ? this.pendingNativeOperation
        : pendingNativeOperation as AgentChatNativeOperation?,
    historyBefore: identical(historyBefore, _unchanged)
        ? this.historyBefore
        : historyBefore as String?,
  );

  bool get neverSent =>
      items.isEmpty &&
      turns.isEmpty &&
      historyBefore == null &&
      pendingNativeOperation == null;

  bool get hasSelection => providerInstanceId.isNotEmpty || provider.isNotEmpty;
}

const Object _unchanged = Object();

/// `agentChat.history`: items older than the thread's oldest loaded item.
class const AgentChatHistoryPage({
  final List<AgentChatItem> items = const <AgentChatItem>[],
  final List<AgentChatTurn> turns = const <AgentChatTurn>[],
  final String? historyBefore,
}) {
  factory fromJson(Object? value) {
    final json = agentChatJsonMap(value);
    return AgentChatHistoryPage(
      items: agentChatItemsFromJson(json['items']),
      turns: agentChatTurnsFromJson(json['turns']),
      historyBefore: agentChatJsonString(json['historyBefore']),
    );
  }
}

List<AgentChatItem> agentChatItemsFromJson(Object? value) => <AgentChatItem>[
  for (final item in agentChatJsonList(value))
    if (item is Map) AgentChatItem.fromJson(item),
];

List<AgentChatTurn> agentChatTurnsFromJson(Object? value) => <AgentChatTurn>[
  for (final turn in agentChatJsonList(value))
    if (turn is Map) AgentChatTurn.fromJson(turn),
];

List<AgentChatRequest> agentChatRequestsFromJson(Object? value) =>
    <AgentChatRequest>[
      for (final request in agentChatJsonList(value))
        if (request is Map) AgentChatRequest.fromJson(request),
    ];
