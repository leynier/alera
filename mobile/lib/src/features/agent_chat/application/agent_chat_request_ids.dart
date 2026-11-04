import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'agent_chat_request_ids.g.dart';

const Uuid _uuid = Uuid();

/// One request id per pending New Chat or Reopen, kept until the runtime
/// answers. Pressing again after a timeout or a dropped connection reuses the
/// id, so the runtime returns the chat the first press made instead of a
/// second one. A refusal clears it: the next press is a new request.
class AgentChatRequestIds {
  final Map<String, String> _pending = <String, String>{};

  String _key(String kind, String hostId, String scope) =>
      '$kind\u0000$hostId\u0000$scope';

  String claimCreate(String hostId, String workspaceId) =>
      _pending.putIfAbsent(_key('create', hostId, workspaceId), _uuid.v4);

  void settleCreate(String hostId, String workspaceId) =>
      _pending.remove(_key('create', hostId, workspaceId));

  String claimReopen(String hostId, String chatId) =>
      _pending.putIfAbsent(_key('reopen', hostId, chatId), _uuid.v4);

  void settleReopen(String hostId, String chatId) =>
      _pending.remove(_key('reopen', hostId, chatId));

  String claimClose(String hostId, String chatId) =>
      _pending.putIfAbsent(_key('close', hostId, chatId), _uuid.v4);

  void settleClose(String hostId, String chatId) =>
      _pending.remove(_key('close', hostId, chatId));
}

@Riverpod(keepAlive: true)
AgentChatRequestIds agentChatRequestIds(Ref ref) => AgentChatRequestIds();
