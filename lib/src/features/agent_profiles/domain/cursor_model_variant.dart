/// Effort tokens Cursor appends to a model slug, in display order.
///
/// `xhigh` and `extra-high` are the same level. Grok uses `xhigh`. GPT uses
/// `extra-high`.
const List<String> cursorEffortTokens = <String>[
  'none',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh',
  'extra-high',
  'max',
];

const Map<String, String> _effortLabels = <String, String>{
  'none': 'None',
  'minimal': 'Minimal',
  'low': 'Low',
  'medium': 'Medium',
  'high': 'High',
  'xhigh': 'Extra High',
  'extra-high': 'Extra High',
  'max': 'Max',
};

/// Longest token first so `extra-high` is not read as effort `high`.
const List<String> _effortSuffixes = <String>[
  'extra-high',
  'minimal',
  'medium',
  'xhigh',
  'none',
  'high',
  'max',
  'low',
];

String cursorEffortLabel(String effort) {
  return _effortLabels[effort] ?? effort;
}

/// One published Cursor model slug split into the controls that encode it.
final class CursorModelVariant {
  const CursorModelVariant({
    required this.id,
    required this.family,
    required this.effort,
    required this.thinking,
    required this.fast,
    this.label = '',
    this.catalogIndex = 0,
  });

  final String id;
  final String family;
  final String? effort;
  final bool thinking;
  final bool fast;
  final String label;
  final int catalogIndex;
}

/// Parses a Cursor model slug from the right.
///
/// The order is load-bearing. Older Claude puts `-thinking` after the effort
/// (`claude-4.6-opus-high-thinking`). Fable and Opus 4.8 put it before
/// (`claude-fable-5-1-thinking-high`). `-fast` is always the last suffix.
/// Returns null when the slug is empty or the suffixes consume the family.
CursorModelVariant? parseCursorModelSlug(String slug) {
  final id = slug.trim();
  if (id.isEmpty) {
    return null;
  }
  var rest = id;
  var fast = false;
  var thinking = false;
  final fastRemainder = _withoutSuffix(rest, 'fast');
  if (fastRemainder != null) {
    fast = true;
    rest = fastRemainder;
  }
  final olderThinking = _withoutSuffix(rest, 'thinking');
  if (olderThinking != null) {
    thinking = true;
    rest = olderThinking;
  }
  String? effort;
  for (final token in _effortSuffixes) {
    final remainder = _withoutSuffix(rest, token);
    if (remainder != null) {
      effort = token;
      rest = remainder;
      break;
    }
  }
  if (!thinking) {
    final newerThinking = _withoutSuffix(rest, 'thinking');
    if (newerThinking != null) {
      thinking = true;
      rest = newerThinking;
    }
  }
  if (rest.isEmpty) {
    return null;
  }
  return CursorModelVariant(
    id: id,
    family: rest,
    effort: effort,
    thinking: thinking,
    fast: fast,
  );
}

String? _withoutSuffix(String value, String suffix) {
  final token = '-$suffix';
  if (!value.endsWith(token)) {
    return null;
  }
  return value.substring(0, value.length - token.length);
}
