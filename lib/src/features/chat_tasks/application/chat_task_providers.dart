import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/infra/runtime_host_agent_chat_transport.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/runs/infra/foreground_board_watch.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_task_providers.g.dart';

/// Recovery is event-driven: a reconnect or a task change reads again, so a
/// failed read never starts a hidden retry loop.
Duration? chatTaskNoRetry(int count, Object error) => null;

/// How many attention rows the status-bar chip and the rail count.
const int chatTaskAttentionLimit = 100;

@Riverpod(keepAlive: true)
AgentChatOrchestrationRepository chatTaskRepository(Ref ref) =>
    RuntimeAgentChatOrchestrationRepository(
      RuntimeHostAgentChatTransport(ref.watch(runtimeHostClientProvider)),
    );

/// Whether the connected runtime runs chat tasks. An unreachable runtime
/// reads as unsupported, so no entry point is offered that would fail.
@Riverpod(keepAlive: true)
Future<bool> chatTasksSupported(Ref ref) async {
  try {
    return await ref.watch(chatTaskRepositoryProvider).supported();
  } on Object {
    return false;
  }
}

/// One Activity list, read again on every change that may touch it. Hidden
/// windows do no reads.
@Riverpod(retry: chatTaskNoRetry)
Stream<AgentChatTaskPage> chatTaskList(Ref ref, AgentChatTaskQuery query) {
  final repository = ref.watch(chatTaskRepositoryProvider);
  return foregroundBoardWatch(
    ref.watch(appForegroundProvider),
    () => repository.watchTasks(query),
  );
}

/// Tasks waiting for input, or failed and not reviewed: the Activity count.
/// The app-wide notification coordinator also consumes this paused stream.
@Riverpod(keepAlive: true, retry: chatTaskNoRetry)
Stream<AgentChatTaskPage> chatTaskAttention(Ref ref) {
  final repository = ref.watch(chatTaskRepositoryProvider);
  return foregroundBoardWatch(
    ref.watch(appForegroundProvider),
    () => repository.watchTasks(
      const AgentChatTaskQuery(attention: true, limit: chatTaskAttentionLimit),
    ),
  );
}

/// One task, live. Reading it never acknowledges its result.
@Riverpod(retry: chatTaskNoRetry)
Stream<AgentChatTask> chatTaskDetail(Ref ref, String taskId) {
  final repository = ref.watch(chatTaskRepositoryProvider);
  return foregroundBoardWatch(
    ref.watch(appForegroundProvider),
    () => repository.watchTask(taskId),
  );
}

/// The open requests of a task's child chat, read again whenever the task
/// changes.
@riverpod
Future<List<AgentChatTaskRequest>> chatTaskRequests(
  Ref ref,
  String taskId,
) async {
  final task = await ref.watch(chatTaskDetailProvider(taskId).future);
  if (task.pendingRequestCount == 0 &&
      task.status != AgentChatTaskStatus.needsInput) {
    return const <AgentChatTaskRequest>[];
  }
  return ref.watch(chatTaskRepositoryProvider).requests(taskId: taskId);
}

/// Whether a delegation may choose the child's reasoning effort. Without it
/// no effort control appears.
@riverpod
Future<bool> chatTaskEffortSupported(Ref ref) async {
  try {
    return await ref.watch(chatTaskRepositoryProvider).supportsEffort();
  } on Object {
    return false;
  }
}

@riverpod
Future<AgentChatOrchestrationCapabilities> chatTaskCapabilities(Ref ref) =>
    ref.watch(chatTaskRepositoryProvider).capabilities();

/// The agents a delegation can start: the providers of the workspace's own
/// host when it exists, else the runtime's catalog, with the runtime's
/// orchestration flags either way.
@riverpod
Future<AgentChatOrchestrationCapabilities> chatTaskAgentCatalog(
  Ref ref,
  String? workspaceId,
) async {
  final capabilities = await ref.watch(chatTaskCapabilitiesProvider.future);
  if (workspaceId == null) return capabilities;
  final providers = await ref.watch(
    agentChatProviderCatalogProvider(workspaceId).future,
  );
  return capabilities.withProviders(providers);
}

/// Chats across every project and host, for the Existing Chat target.
@riverpod
Future<List<AgentChatDirectoryEntry>> chatTaskDirectory(Ref ref) =>
    ref.watch(chatTaskRepositoryProvider).chats();

/// A chat's title and place, for the sender of a chat message.
@riverpod
Future<AgentChatDirectoryEntry> chatTaskChat(Ref ref, String chatId) async =>
    (await ref.watch(chatTaskRepositoryProvider).read(chatId, limit: 1)).chat;
