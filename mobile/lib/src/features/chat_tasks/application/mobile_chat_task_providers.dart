import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/infra/mobile_agent_chat_transport.dart';
import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'mobile_chat_task_providers.g.dart';

/// The attention list behind the Activity count.
const AgentChatTaskQuery mobileChatTaskAttentionQuery = AgentChatTaskQuery(
  attention: true,
  limit: 100,
);

/// Chat orchestration over the paired runtime: the same connection the
/// workspace and chat screens use, so it rebuilds with every reconnect.
@riverpod
Future<AgentChatOrchestrationRepository> mobileChatTaskRepository(
  Ref ref,
  String hostId,
) async => RuntimeAgentChatOrchestrationRepository(
  MobileAgentChatTransport(
    await ref.watch(mobileAgentChatClientProvider(hostId).future),
  ),
);

/// Whether the paired runtime runs chat tasks. An older runtime, a client
/// without chats or an unreachable host is a plain no, never an error.
@riverpod
Future<bool> mobileChatTasksSupported(Ref ref, String hostId) async {
  try {
    final Object client = await ref.watch(
      workspaceClientProvider(hostId).future,
    );
    return client is MobileAgentChatClient &&
        client.runtimeCapabilities.contains(
          AgentChatOrchestrationWire.capability,
        );
  } on Object {
    return false;
  }
}

/// Allocates request ids; tests pin it.
@Riverpod(keepAlive: true)
String Function() mobileChatTaskIdGenerator(Ref ref) =>
    () => const Uuid().v4();

@riverpod
Future<AgentChatTaskActions> mobileChatTaskActions(
  Ref ref,
  String hostId,
) async => AgentChatTaskActions(
  await ref.watch(mobileChatTaskRepositoryProvider(hostId).future),
  ref.watch(mobileChatTaskIdGeneratorProvider),
);

/// One list, read again on every change that may touch it.
@riverpod
Stream<AgentChatTaskPage> mobileChatTaskList(
  Ref ref,
  String hostId,
  AgentChatTaskQuery query,
) async* {
  final repository = await ref.watch(
    mobileChatTaskRepositoryProvider(hostId).future,
  );
  yield* repository.watchTasks(query);
}

/// Tasks waiting for input, or failed and not reviewed.
@riverpod
Future<int> mobileChatTaskAttentionCount(Ref ref, String hostId) async {
  if (!await ref.watch(mobileChatTasksSupportedProvider(hostId).future)) {
    return 0;
  }
  final page = await ref.watch(
    mobileChatTaskListProvider(hostId, mobileChatTaskAttentionQuery).future,
  );
  return page.tasks.length;
}

/// One task, live. Reading it never acknowledges its result.
@riverpod
Stream<AgentChatTask> mobileChatTaskDetail(
  Ref ref,
  String hostId,
  String taskId,
) async* {
  final repository = await ref.watch(
    mobileChatTaskRepositoryProvider(hostId).future,
  );
  yield* repository.watchTask(taskId);
}

@riverpod
Future<List<AgentChatTaskRequest>> mobileChatTaskRequests(
  Ref ref,
  String hostId,
  String taskId,
) async {
  final task = await ref.watch(
    mobileChatTaskDetailProvider(hostId, taskId).future,
  );
  if (task.pendingRequestCount == 0 &&
      task.status != AgentChatTaskStatus.needsInput) {
    return const <AgentChatTaskRequest>[];
  }
  final repository = await ref.watch(
    mobileChatTaskRepositoryProvider(hostId).future,
  );
  return repository.requests(taskId: taskId);
}

/// The agents a delegation can start: the workspace's own host catalog when
/// the workspace exists, else the runtime's, with its orchestration flags.
@riverpod
Future<AgentChatOrchestrationCapabilities> mobileChatTaskAgentCatalog(
  Ref ref,
  String hostId,
  String? workspaceId,
) async {
  final repository = await ref.watch(
    mobileChatTaskRepositoryProvider(hostId).future,
  );
  final capabilities = await repository.capabilities();
  if (workspaceId == null) return capabilities;
  return capabilities.withProviders(
    await ref.watch(agentChatProvidersProvider(hostId, workspaceId).future),
  );
}

/// Chats across every project and host, for the Existing Chat target.
@riverpod
Future<List<AgentChatDirectoryEntry>> mobileChatTaskDirectory(
  Ref ref,
  String hostId,
) async =>
    (await ref.watch(mobileChatTaskRepositoryProvider(hostId).future)).chats();

/// A chat's title and place, for the sender of a chat message.
@riverpod
Future<AgentChatDirectoryEntry> mobileChatTaskChat(
  Ref ref,
  String hostId,
  String chatId,
) async {
  final repository = await ref.watch(
    mobileChatTaskRepositoryProvider(hostId).future,
  );
  return (await repository.read(chatId, limit: 1)).chat;
}

/// Projects and workspaces the task screens name and offer as targets.
class const MobileChatTaskPlaces({
  final List<ProjectSummary> projects = const <ProjectSummary>[],
  final List<WorkspaceSummary> workspaces = const <WorkspaceSummary>[],
}) {
  String? projectName(String? id) =>
      projects.where((project) => project.id == id).firstOrNull?.name;

  WorkspaceSummary? workspace(String? id) =>
      workspaces.where((workspace) => workspace.id == id).firstOrNull;
}

@riverpod
Future<MobileChatTaskPlaces> mobileChatTaskPlaces(
  Ref ref,
  String hostId,
) async {
  final client = await ref.watch(workspaceClientProvider(hostId).future);
  final (projects, workspaces) = await (
    client.listProjects(),
    client.listWorkspaces(),
  ).wait;
  return MobileChatTaskPlaces(projects: projects, workspaces: workspaces);
}

/// The group Chat Tasks shows on this host, kept while the app runs.
@Riverpod(keepAlive: true)
class MobileChatTaskFilter extends _$MobileChatTaskFilter {
  @override
  AgentChatTaskBucket? build(String hostId) => null;

  void select(AgentChatTaskBucket? bucket) => state = bucket;
}

/// The Delegate Task form of one host.
@riverpod
class MobileDelegateChatTaskForm extends _$MobileDelegateChatTaskForm {
  @override
  AgentChatDelegateDraft build(String hostId) => const AgentChatDelegateDraft();

  void update(AgentChatDelegateDraft draft) => state = draft;
}
