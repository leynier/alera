import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/presentation/widgets/markdown_helpers.dart';
import 'package:alera/src/shared/presentation/toast/alera_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:highlight/highlight.dart' show highlight, Node;
import 'package:markdown/markdown.dart' as md;

/// Custom [MarkdownElementBuilder] for `<pre>` blocks that applies
/// syntax highlighting via the `highlight` package.
///
/// The outer decoration (codeblockDecoration) is applied by builder.dart,
/// so this builder only provides the highlighted content widget.
class CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    // Suppress the default code rendering; we handle it in
    // visitElementAfterWithContext instead.
    return null;
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final code = element.textContent;
    final language = _extractLanguage(element);
    final result = language != null
        ? highlight.parse(code, language: language)
        : highlight.parse(code, autoDetection: true);
    final spans = <TextSpan>[];
    for (final node in result.nodes ?? <Node>[]) {
      _buildSpans(node, spans, null);
    }
    return SelectionContainer.disabled(
      child: _CodeBlockWithCopy(code: code, spans: spans),
    );
  }

  static String? _extractLanguage(md.Element element) {
    if (element.children == null || element.children!.isEmpty) return null;
    final first = element.children!.first;
    if (first is! md.Element) return null;
    final cls = first.attributes['class'];
    if (cls == null || !cls.startsWith('language-')) return null;
    return cls.substring('language-'.length);
  }

  static void _buildSpans(Node node, List<TextSpan> out, String? parentClass) {
    final cls = node.className ?? parentClass;
    if (node.value != null) {
      out.add(TextSpan(text: node.value, style: _styleFor(cls)));
      return;
    }
    if (node.children != null) {
      for (final child in node.children!) {
        _buildSpans(child, out, cls);
      }
    }
  }

  static TextStyle? _styleFor(String? className) {
    if (className == null) return null;
    final color = _tokenColors[className];
    if (color == null) return null;
    return TextStyle(color: color);
  }

  static const _tokenColors = <String, Color>{
    // Keywords and control flow
    'keyword': AleraTokens.info,
    'built_in': AleraTokens.info,
    'literal': AleraTokens.info,
    'meta-keyword': AleraTokens.info,
    // Strings and templates
    'string': AleraTokens.success,
    'regexp': AleraTokens.success,
    'template-variable': AleraTokens.success,
    'addition': AleraTokens.success,
    // Comments and docs
    'comment': AleraTokens.foregroundFaint,
    'doctag': AleraTokens.foregroundFaint,
    'quote': AleraTokens.foregroundFaint,
    // Numbers
    'number': AleraTokens.warning,
    // Types, classes, titles
    'type': AleraTokens.accent,
    'title': AleraTokens.accent,
    'class': AleraTokens.accent,
    'title.class': AleraTokens.accent,
    'title.class.inherited': AleraTokens.accent,
    'title.function': AleraTokens.accent,
    // Meta / annotations
    'meta': AleraTokens.foregroundMuted,
    'meta-string': AleraTokens.foregroundMuted,
    // Attributes / symbols
    'attr': AleraTokens.foregroundMuted,
    'attribute': AleraTokens.foregroundMuted,
    'symbol': AleraTokens.warning,
    'variable': AleraTokens.foreground,
    'params': AleraTokens.foreground,
    // Deletion (diff)
    'deletion': AleraTokens.error,
    // Section headers
    'section': AleraTokens.accent,
    'selector-tag': AleraTokens.info,
    'selector-id': AleraTokens.accent,
    'selector-class': AleraTokens.success,
  };
}

class _CodeBlockWithCopy extends StatefulWidget {
  const _CodeBlockWithCopy({required this.code, required this.spans});
  final String code;
  final List<TextSpan> spans;
  @override
  State<_CodeBlockWithCopy> createState() => _CodeBlockWithCopyState();
}

class _CodeBlockWithCopyState extends State<_CodeBlockWithCopy> {
  bool _isHovered = false;

  Future<void> _copy() async {
    if (widget.code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    AleraToast.show(
      context,
      message: 'Code copied',
      tone: AleraToastTone.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool effectivelyActive = !mouseIsConnected() || _isHovered;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Stack(
        children: <Widget>[
          _ScrollControllerBuilder(
            builder:
                (BuildContext ctx, ScrollController controller, Widget? child) {
                  return Scrollbar(
                    controller: controller,
                    child: SingleChildScrollView(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(AleraTokens.space12),
                      child: child,
                    ),
                  );
                },
            child: Text.rich(
              TextSpan(style: AleraTokens.monoStyle, children: widget.spans),
            ),
          ),
          Positioned(
            top: AleraTokens.space4,
            right: AleraTokens.space4,
            child: InkWell(
              onTap: effectivelyActive ? _copy : null,
              mouseCursor: effectivelyActive
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space4,
                  vertical: AleraTokens.space2,
                ),
                child: Icon(
                  Icons.content_copy,
                  size: 12,
                  color: effectivelyActive
                      ? AleraTokens.foregroundFaint
                      : Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal reproduction of the private _ScrollControllerBuilder from
/// flutter_markdown_plus so that code blocks get their own ScrollController.
class _ScrollControllerBuilder extends StatefulWidget {
  const _ScrollControllerBuilder({required this.builder, required this.child});
  final Widget Function(BuildContext, ScrollController, Widget?) builder;
  final Widget child;
  @override
  State<_ScrollControllerBuilder> createState() =>
      _ScrollControllerBuilderState();
}

class _ScrollControllerBuilderState extends State<_ScrollControllerBuilder> {
  late final ScrollController _controller;
  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _controller, widget.child);
}
