/// Wire names shared by the runtime, the desktop app and the phone.
abstract final class AgentChatWire {
  static const String capability = 'agentChatV1';
  static const String tabKind = 'agentChat';

  /// Tab payload keys. [legacyChatIdKey] is read but never written.
  static const String chatIdKey = 'chatId';
  static const String legacyChatIdKey = 'agentChatId';
  static const String providerKey = 'provider';
  static const String providerInstanceIdKey = 'providerInstanceId';
  static const String modelKey = 'model';

  static const String changedEvent = 'agentChatChanged';
  static const String listChangedEvent = 'agentChatsChanged';

  static const String providers = 'agentChat.providers';
  static const String create = 'agentChat.create';
  static const String reopen = 'agentChat.reopen';
  static const String snapshot = 'agentChat.snapshot';
  static const String history = 'agentChat.history';
  static const String payload = 'agentChat.payload';
  static const String send = 'agentChat.send';
  static const String queueCancel = 'agentChat.queueCancel';
  static const String interrupt = 'agentChat.interrupt';
  static const String respond = 'agentChat.respond';
  static const String configure = 'agentChat.configure';
  static const String rename = 'agentChat.rename';
  static const String recover = 'agentChat.recover';
  static const String close = 'agentChat.close';
  static const String list = 'agentChat.list';
}

/// Events every transport adapter emits for its own connection lifecycle,
/// whatever its native names are.
abstract final class AgentChatTransportEvents {
  static const String connected = 'agentChat.transport.connected';
  static const String disconnected = 'agentChat.transport.disconnected';
}

final class const AgentChatTransportEvent(
  final String name,
  final Map<String, Object?> payload,
);

/// The runtime connection as the shared repository needs it. Each app adapts
/// its own runtime client: desktop over the local socket, the phone over its
/// paired gateway. Failures must surface as [AgentChatRequestException] or
/// [AgentChatConnectionException].
abstract interface class AgentChatTransport {
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  });

  Stream<AgentChatTransportEvent> get events;

  Future<bool> supportsCapability(String capability);
}

/// The runtime rejected a request; [code] is its `errorCode` when it sent one.
final class const AgentChatRequestException({
  required final String message,
  final String? code,
  final Map<String, Object?> details = const <String, Object?>{},
}) implements Exception {
  @override
  String toString() => message;
}

/// The request never got an answer: the connection closed or timed out. A
/// mutation may still have been applied; retry with the same request id.
final class const AgentChatConnectionException(final String message)
    implements Exception {
  @override
  String toString() => message;
}

/// The runtime does not advertise [AgentChatWire.capability].
final class const AgentChatUpdateRequired() implements Exception {
  @override
  String toString() =>
      'This Alera runtime does not support agent chats yet. Update it to '
      'continue.';
}
