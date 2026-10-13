import 'package:alera_agent_chat/src/agent_chat_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_catalog.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_query.dart';
import 'package:alera_agent_chat/src/agent_chat_orchestration_task.dart';
import 'package:alera_agent_chat/src/agent_chat_snapshot.dart';

/// When a bounded wait returns.
enum AgentChatTaskWaitUntil(final String wire) {
  all('all'),
  any('any'),
}

/// Everything the apps ask of chat orchestration. People on the desktop and
/// on a paired phone have the same verbs; nothing here selects a workspace
/// or a tab. Mutations take a caller-allocated request id so a retry after a
/// dropped connection replays the runtime's receipt instead of acting twice.
abstract interface class AgentChatOrchestrationRepository {
  /// Whether the runtime advertises chat orchestration at all.
  Future<bool> supported();

  Future<AgentChatOrchestrationCapabilities> capabilities();

  Future<AgentChatDelegateResult> delegate(AgentChatDelegateInput input);

  Future<AgentChatTaskMessageResult> send(AgentChatTaskMessageInput input);

  /// Reads a task. [acknowledge] takes its settled result from whoever owns
  /// it; the apps pass it only for tasks a person owns.
  Future<AgentChatTask> task(String taskId, {bool acknowledge = false});

  Future<AgentChatTaskPage> tasks(AgentChatTaskQuery query, {String? cursor});

  /// Waits at most [waitSeconds], capped at the runtime's maximum, for the
  /// tasks to settle. A timeout is an ordinary answer: wait again for more.
  Future<AgentChatTaskWaitResult> wait(
    List<String> taskIds, {
    int waitSeconds = 50,
    AgentChatTaskWaitUntil until = AgentChatTaskWaitUntil.all,
  });

  /// Cancels a task and every task it started; workspaces it created stay.
  Future<AgentChatTask> cancel(String taskId, {required String requestId});

  Future<void> interrupt(String chatId, {required String requestId});

  Future<List<AgentChatTaskRequest>> requests({String? taskId, String? chatId});

  Future<void> respond({
    required String chatId,
    required String requestId,
    required String runtimeRequestId,
    required AgentChatResponse response,
  });

  Future<AgentChatSnapshot> configure(
    String chatId, {
    required String requestId,
    required AgentChatConfiguration configuration,
  });

  Future<AgentChatTranscript> read(String chatId, {int? limit});

  /// Chats across every project and host the runtime knows.
  Future<List<AgentChatDirectoryEntry>> chats({
    String? projectId,
    String? workspaceId,
    String? hostId,
    bool includeArchived = false,
  });

  /// `chatOrchestrationChanged`, plus [AgentChatTaskChange.any] after a
  /// reconnect.
  Stream<AgentChatTaskChange> changes();

  /// The first page of [query], read again on every change that may touch
  /// it. A dropped connection surfaces as an error; the next reconnect reads
  /// again.
  Stream<AgentChatTaskPage> watchTasks(AgentChatTaskQuery query);

  /// One task, read again on every change that may touch it. Reading never
  /// acknowledges its result.
  Stream<AgentChatTask> watchTask(String taskId);
}
