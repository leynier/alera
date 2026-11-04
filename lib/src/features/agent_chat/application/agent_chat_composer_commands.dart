import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_composer_commands.g.dart';

enum AgentChatComposerCommandKind {
  /// Put the caret in the chat's composer.
  focus,

  /// Open the chat's agent and model picker (Choose Model).
  chooseModel,
}

/// A request for one mounted chat's composer. [serial] makes a repeated
/// request for the same chat a new state, so listeners see every press.
final class const AgentChatComposerCommand({
  required final String chatId,
  required final AgentChatComposerCommandKind kind,
  required final int serial,
});

/// Commands that keyboard actions and New Agent Chat send to the composer of
/// a chat that is already on screen. A chat that is not mounted ignores them.
@Riverpod(keepAlive: true)
class AgentChatComposerCommands extends _$AgentChatComposerCommands {
  int _serial = 0;

  @override
  AgentChatComposerCommand? build() => null;

  void focus(String chatId) =>
      _send(chatId, AgentChatComposerCommandKind.focus);

  void chooseModel(String chatId) =>
      _send(chatId, AgentChatComposerCommandKind.chooseModel);

  void _send(String chatId, AgentChatComposerCommandKind kind) => state =
      AgentChatComposerCommand(chatId: chatId, kind: kind, serial: ++_serial);
}
