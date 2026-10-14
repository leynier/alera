import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_task_dock_expansion.g.dart';

/// Which chats show their Tasks dock expanded. Session state, so a tab switch
/// keeps it and a restart starts collapsed.
@Riverpod(keepAlive: true)
class ChatTaskDockExpansion extends _$ChatTaskDockExpansion {
  @override
  Set<String> build() => const <String>{};

  void set(String chatId, {required bool expanded}) {
    if (state.contains(chatId) == expanded) return;
    state = expanded
        ? Set<String>.unmodifiable(<String>{...state, chatId})
        : Set<String>.unmodifiable(<String>{
            for (final id in state)
              if (id != chatId) id,
          });
  }
}
