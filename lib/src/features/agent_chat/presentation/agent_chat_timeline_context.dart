import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/foundation.dart';

/// Callbacks the timeline rows need, bundled so cached rows rebuild only when
/// one of them actually changes. Requests are answered from the request
/// dock, not from timeline rows.
final class const AgentChatTimelineActions({
  required final String chatId,
  required final ValueChanged<String> onRetrySend,
  required final ValueChanged<String> onEditSend,
  required final ValueChanged<String> onOpenLink,
  required final ValueChanged<String> onOpenFile,
  required final VoidCallback onImplementPlan,
  final String? implementablePlanId,

  /// Puts the caret in the composer to answer the plan
  /// [implementablePlanId] with changes, staying in plan mode.
  final VoidCallback? onRefinePlan,

  /// History controls of a settled turn, by turn id. Pass each only when the
  /// runtime advertises its capability (`agentChatForkV1`,
  /// `agentChatRewindV1`, `agentChatTurnDiffV1`); a null one hides the control.
  /// [onRewindTurn] is the transcript rewind, which never touches files.
  final ValueChanged<String>? onForkTurn,
  final ValueChanged<String>? onRewindTurn,
  final ValueChanged<String>? onShowTurnDiff,

  /// Native history, passed only when [AgentChatRewindOptions.resolve]
  /// offers it: a rollback of the provider's own conversation, and a file
  /// rewind to the provider's checkpoint.
  final ValueChanged<String>? onNativeRewindTurn,
  final ValueChanged<String>? onRewindFilesTurn,
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
