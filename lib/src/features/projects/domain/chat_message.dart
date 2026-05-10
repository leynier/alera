enum ChatMessageRole { user, assistant, system }

ChatMessageRole _roleFromWire(String value) {
  for (final role in ChatMessageRole.values) {
    if (role.name == value) {
      return role;
    }
  }
  throw StateError('Unknown chat message role: $value');
}

class ChatMessage {
  const ChatMessage({
    required this.chatId,
    required this.seq,
    required this.role,
    required this.text,
    this.toolCallsJson,
    this.tokensIn,
    this.tokensOut,
    this.costUsd,
    this.turnId,
    required this.createdAt,
  });

  final String chatId;
  final int seq;
  final ChatMessageRole role;
  final String text;
  final String? toolCallsJson;
  final int? tokensIn;
  final int? tokensOut;
  final double? costUsd;
  final String? turnId;
  final DateTime createdAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'chatId': chatId,
      'seq': seq,
      'role': role.name,
      'text': text,
      'toolCallsJson': toolCallsJson,
      'tokensIn': tokensIn,
      'tokensOut': tokensOut,
      'costUsd': costUsd,
      'turnId': turnId,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }

  factory ChatMessage.fromJson(Map<String, Object?> json) {
    final chatId = json['chatId'];
    final seq = json['seq'];
    final role = json['role'];
    final text = json['text'];
    final createdAt = json['createdAt'];
    if (chatId is! String || chatId.isEmpty) {
      throw StateError('Chat message missing chatId');
    }
    if (seq is! int) {
      throw StateError('Chat message missing seq');
    }
    if (role is! String) {
      throw StateError('Chat message missing role');
    }
    if (text is! String) {
      throw StateError('Chat message missing text');
    }
    if (createdAt is! String) {
      throw StateError('Chat message missing createdAt');
    }
    return ChatMessage(
      chatId: chatId,
      seq: seq,
      role: _roleFromWire(role),
      text: text,
      toolCallsJson: json['toolCallsJson'] as String?,
      tokensIn: json['tokensIn'] as int?,
      tokensOut: json['tokensOut'] as int?,
      costUsd: (json['costUsd'] as num?)?.toDouble(),
      turnId: json['turnId'] as String?,
      createdAt: DateTime.parse(createdAt).toUtc(),
    );
  }
}
