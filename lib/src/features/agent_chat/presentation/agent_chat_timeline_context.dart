import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/foundation.dart';

/// Callbacks the timeline rows need, bundled so cached rows rebuild only when
/// one of them actually changes.
final class const AgentChatTimelineActions({
  required final String chatId,
  required final void Function(
    AgentChatRequest request,
    AgentChatResponse response,
  )
  onRespond,
  required final ValueChanged<String> onRetrySend,
  required final ValueChanged<String> onEditSend,
  required final ValueChanged<String> onOpenLink,
  required final ValueChanged<String> onOpenFile,
  required final VoidCallback onImplementPlan,
  final String? implementablePlanId,
});

/// Which collapsible rows the user opened or closed, by row key. Kept above
/// the lazily built list so a row scrolled out of view and back keeps its
/// state; rows without an override follow their default.
final class AgentChatExpansion {
  final Map<String, bool> _overrides = <String, bool>{};

  bool isExpanded(String key, {required bool byDefault}) =>
      _overrides[key] ?? byDefault;

  void set(String key, {required bool expanded}) => _overrides[key] = expanded;

  void retainWhere(bool Function(String key) keep) =>
      _overrides.removeWhere((key, _) => !keep(key));
}
