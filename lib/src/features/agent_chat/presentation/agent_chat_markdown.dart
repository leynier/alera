import 'dart:collection';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/markdown/alera_code_block.dart';
import 'package:alera/src/design_system/markdown/alera_markdown_view.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_markdown_math.dart';
import 'package:alera/src/features/settings/domain/editor_syntax_theme_catalog.dart';
import 'package:flutter/material.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

// Highlighting runs on the UI isolate, so it is bounded: only finished fences,
// only up to this size, and each result is cached for later rebuilds.
const int _maxHighlightedCodeLength = 12000;
const int _highlightCacheLimit = 64;

final LinkedHashMap<(String, String), TextSpan?> _highlightCache =
    LinkedHashMap<(String, String), TextSpan?>();

/// Agent output rendered as Markdown with highlighted code blocks and TeX
/// math, typeset in Flutter. Images are not fetched: agent text is untrusted
/// and a remote image would leak that the chat was read.
class const AgentChatMarkdown({
  super.key,
  required final String data,
  final ValueChanged<String>? onOpenLink,
  final bool muted = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: muted ? AleraTokens.foregroundMuted : AleraTokens.foreground,
      height: 1.45,
    );
    return AleraMarkdownView(
      data: agentChatDollarMath(data),
      style: style,
      onLinkTap: onOpenLink,
      imageBuilder: (context, source, width, height) => Tooltip(
        message: source,
        child: const Icon(
          AleraIcons.imageError,
          size: AleraTokens.iconLg,
          color: AleraTokens.foregroundMuted,
        ),
      ),
      codeBuilder: (context, language, code, closed) => AleraCodeBlock(
        code: code,
        language: language,
        highlighted: closed ? agentChatHighlightCode(code, language) : null,
      ),
    );
  }
}

TextSpan? agentChatHighlightCode(String code, String language) {
  final normalized = language.trim().toLowerCase();
  final mode = builtinAllLanguages[normalized];
  if (mode == null || code.length > _maxHighlightedCodeLength) return null;
  final key = (normalized, code);
  if (_highlightCache.containsKey(key)) {
    final cached = _highlightCache.remove(key);
    _highlightCache[key] = cached;
    return cached;
  }
  TextSpan? span;
  try {
    final highlighter = Highlight()..registerLanguage(normalized, mode);
    final result = highlighter.highlight(code: code, language: normalized);
    final renderer = TextSpanRenderer(
      AleraTokens.monoStyle,
      editorSyntaxThemeForName(EditorSyntaxThemeNames.alera),
    );
    result.render(renderer);
    span = renderer.span;
  } on Object {
    span = null;
  }
  _highlightCache[key] = span;
  while (_highlightCache.length > _highlightCacheLimit) {
    _highlightCache.remove(_highlightCache.keys.first);
  }
  return span;
}
