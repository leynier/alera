part of 'codex_chat_surface.dart';

class _CodexMarkdownCodeBlock extends StatefulWidget {
  const _CodexMarkdownCodeBlock({
    required this.language,
    required this.code,
    required this.closed,
  });

  final String language;
  final String code;
  final bool closed;

  @override
  State<_CodexMarkdownCodeBlock> createState() =>
      _CodexMarkdownCodeBlockState();
}

class _CodexMarkdownCodeBlockState extends State<_CodexMarkdownCodeBlock> {
  TextSpan? _highlighted;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _highlighted = _highlightCodexCode(widget);
  }

  @override
  void didUpdateWidget(covariant _CodexMarkdownCodeBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.language != widget.language ||
        oldWidget.closed != widget.closed) {
      _highlighted = _highlightCodexCode(widget);
    }
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.bg,
        border: Border.all(color: AleraTokens.borderSubtle),
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.language.trim().isNotEmpty || _hovered) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
                vertical: AleraTokens.space4,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      widget.language.trim(),
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: AleraTokens.foregroundMuted),
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: _hovered ? 1 : 0,
                    duration: AleraTokens.durationFast,
                    child: AleraIconButton(
                      tooltip: 'Copy Code',
                      icon: AleraIcons.copy,
                      onPressed: () =>
                          _copyCodexText(context, widget.code, 'Code copied'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              height: AleraTokens.dividerExtent,
              color: AleraTokens.borderSubtle,
            ),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: SelectableText.rich(
              _highlighted ??
                  TextSpan(
                    text: widget.code,
                    style: AleraTokens.monoStyle.copyWith(
                      color: AleraTokens.foreground,
                    ),
                  ),
            ),
          ),
        ],
      ),
    ),
  );
}

TextSpan? _highlightCodexCode(_CodexMarkdownCodeBlock widget) {
  final language = widget.language.trim().toLowerCase();
  // Partial fences change on every streamed chunk. Waiting until completion
  // avoids re-running a syntax parser for each visible update.
  if (!widget.closed ||
      language.isEmpty ||
      widget.code.length > 12000 ||
      !builtinAllLanguages.containsKey(language)) {
    return null;
  }
  try {
    final highlighter = Highlight()
      ..registerLanguage(language, builtinAllLanguages[language]!);
    final result = highlighter.highlight(code: widget.code, language: language);
    final renderer = TextSpanRenderer(
      AleraTokens.monoStyle,
      editorSyntaxThemeForName(EditorSyntaxThemeNames.alera),
    );
    result.render(renderer);
    return renderer.span;
  } catch (_) {
    return null;
  }
}
