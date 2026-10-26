/// What the token at the caret asks the composer menu for.
enum AgentChatComposerTriggerKind {
  /// `@query` at a word boundary: workspace files to attach.
  mention,

  /// `/query` at a word start that is not a path: commands, and the
  /// agent's own commands too when it opens the prompt.
  command,

  /// `$query` (any currency sigil) at a word start that is not an amount
  /// such as `$5` or `$10k`: the agent's skills.
  skill,
}

/// The token at the caret that opens the composer menu. [start] and [end]
/// span the whole token, the `@` or `/` included, so picking replaces it even
/// when the caret sits inside it.
final class const AgentChatComposerTrigger({
  required final AgentChatComposerTriggerKind kind,
  required final String query,
  required final int start,
  required final int end,
}) {
  @override
  bool operator ==(Object other) =>
      other is AgentChatComposerTrigger &&
      other.kind == kind &&
      other.query == query &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, query, start, end);

  @override
  String toString() => 'AgentChatComposerTrigger($kind, "$query", $start-$end)';
}

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x0A || unit == 0x09 || unit == 0x0D;

final RegExp _currencySigil = RegExp(r'^\p{Sc}', unicode: true);

/// T3 Code's `isCurrencyAmountQuery`: `$5`, `€9.99` and `$10k` are money,
/// including the punctuation prose puts after one (`$10k.`, `($5)`).
final RegExp _currencyAmount = RegExp(
  r'^\.?[0-9][0-9,._]*(?:[kKmMbBtT]|[eE][0-9]+)?[.,;:!?)]*$',
);

/// The trigger at the caret of [text], or `null` when the caret is not in an
/// `@`, `/` or skill token, or when the selection is not collapsed
/// ([selectionStart] differs from [selectionEnd]).
///
/// Every trigger counts at the start of a word only, so an email address
/// does not open the file menu, as in T3 Code. A `/` word with a second
/// slash is a path such as `/src/main.dart` and opens nothing; whether the
/// command starts the prompt is [AgentChatComposerTrigger.start] `== 0`,
/// because agents only expand their own commands there. A currency sigil
/// opens skills unless what follows is an amount.
AgentChatComposerTrigger? agentChatComposerTriggerAt(
  String text, {
  required int selectionStart,
  required int selectionEnd,
}) {
  if (selectionStart < 0 || selectionStart != selectionEnd) return null;
  final caret = selectionEnd;
  if (caret > text.length) return null;
  var start = caret;
  while (start > 0 && !_isSpace(text.codeUnitAt(start - 1))) {
    start--;
  }
  if (start == caret) return null;
  var end = caret;
  while (end < text.length && !_isSpace(text.codeUnitAt(end))) {
    end++;
  }
  final sigil = _currencySigil.firstMatch(text.substring(start, caret));
  final kind = switch (text[start]) {
    '@' => AgentChatComposerTriggerKind.mention,
    '/' when !text.substring(start + 1, end).contains('/') =>
      AgentChatComposerTriggerKind.command,
    _ when sigil != null => AgentChatComposerTriggerKind.skill,
    _ => null,
  };
  if (kind == null) return null;
  final queryStart = start + (sigil?.end ?? 1);
  final query = text.substring(queryStart, caret);
  if (kind == AgentChatComposerTriggerKind.skill &&
      _currencyAmount.hasMatch(query)) {
    return null;
  }
  return AgentChatComposerTrigger(
    kind: kind,
    query: query,
    start: start,
    end: end,
  );
}

/// [text] with [trigger]'s token replaced by [replacement], and the caret
/// after it. Removing a token (an empty [replacement]) also drops one space
/// after it when a space or the start of the prompt precedes it, and a
/// [replacement] that ends in a space absorbs the space already there, so
/// the prompt never keeps a double space.
({String text, int caret}) agentChatComposerTriggerReplaced(
  String text,
  AgentChatComposerTrigger trigger, {
  String replacement = '',
}) {
  final start = trigger.start.clamp(0, text.length);
  var end = trigger.end.clamp(start, text.length);
  final followedBySpace = end < text.length && text.codeUnitAt(end) == 0x20;
  if (followedBySpace &&
      (replacement.isEmpty
          ? start == 0 || _isSpace(text.codeUnitAt(start - 1))
          : replacement.endsWith(' '))) {
    end++;
  }
  return (
    text: text.replaceRange(start, end, replacement),
    caret: start + replacement.length,
  );
}
