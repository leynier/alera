import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/markdown/alera_code_block.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

/// Builds the widget for a Markdown image. [source] is the raw URL or path,
/// and [width] and [height] come from a `WxH` alt text when present.
typedef AleraMarkdownImageBuilder = Widget Function(
  BuildContext context,
  String source,
  double? width,
  double? height,
);

/// Builds the widget for a fenced code block. [closed] stays false until the
/// closing fence arrives, as in a reply that is still streaming.
typedef AleraMarkdownCodeBuilder = Widget Function(
  BuildContext context,
  String language,
  String code,
  bool closed,
);

/// Read-only Markdown drawn with Alera's type scale and tokens.
///
/// Selection belongs to the caller: wrap one `SelectionArea` around the page
/// or timeline instead of one per view, so a selection can span several
/// messages. Links are reported through [onLinkTap] and never opened here.
/// Images are not fetched unless [imageBuilder] does it; without one each
/// image draws as a muted icon. Fenced code renders as an [AleraCodeBlock]
/// unless [codeBuilder] takes over. [style] is merged over the default body
/// style (`bodyMedium` in `foreground`).
class const AleraMarkdownView({
  super.key,
  required final String data,
  final ValueChanged<String>? onLinkTap,
  final AleraMarkdownImageBuilder? imageBuilder,
  final AleraMarkdownCodeBuilder? codeBuilder,
  final TextStyle? style,
}) extends StatefulWidget {
  @override
  State<AleraMarkdownView> createState() => _AleraMarkdownViewState();
}

// The package compares its theme by identity and re-parses the whole document
// whenever it changes, so every view shares one instance per app theme.
final Expando<GptMarkdownThemeData> _markdownThemes =
    Expando<GptMarkdownThemeData>();

GptMarkdownThemeData _markdownThemeFor(ThemeData theme) =>
    _markdownThemes[theme] ??= _buildMarkdownTheme(theme);

GptMarkdownThemeData _buildMarkdownTheme(ThemeData theme) {
  final text = theme.textTheme;
  return GptMarkdownThemeData(
    brightness: .dark,
    h1: text.titleLarge,
    h2: text.titleMedium?.copyWith(fontWeight: .w600),
    h3: text.titleSmall?.copyWith(fontWeight: .w600),
    h4: text.bodyMedium?.copyWith(fontWeight: .w600),
    h5: text.bodySmall?.copyWith(
      color: AleraTokens.foreground,
      fontWeight: .w600,
    ),
    h6: text.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
      fontWeight: .w600,
    ),
    hrLineColor: AleraTokens.borderSubtle,
    hrLinePadding: const .symmetric(vertical: AleraTokens.space4),
    linkColor: AleraTokens.info,
    linkHoverColor: AleraTokens.foreground,
    highlightColor: AleraTokens.accentSubtle,
    autoAddDividerLineAfterH1: false,
    inlineCode: InlineCodeStyle(
      fontFamily: AleraTokens.monoStyle.fontFamily,
      color: AleraTokens.foreground,
      backgroundColor: AleraTokens.accentSubtle,
      borderColor: AleraTokens.borderSubtle,
      borderRadius: const .circular(AleraTokens.radiusXs),
    ),
  );
}

class _AleraMarkdownViewState extends State<AleraMarkdownView> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .copyWith(color: AleraTokens.foreground, height: 1.45)
        .merge(widget.style);
    return GptMarkdownTheme(
      gptThemeData: _markdownThemeFor(theme),
      child: DefaultTextStyle(
        style: bodyStyle,
        child: GptMarkdown(
          widget.data,
          style: bodyStyle,
          onLinkTap: _handleLinkTap,
          imageBuilder: _buildImage,
          codeBuilder: _buildCode,
        ),
      ),
    );
  }

  // The package keeps its parsed spans, and the callbacks captured in them,
  // until the text changes; reading `widget` at call time keeps them current.
  void _handleLinkTap(String url, String title) => widget.onLinkTap?.call(url);

  Widget _buildImage(
    BuildContext context,
    String source,
    double? width,
    double? height,
  ) {
    final builder = widget.imageBuilder;
    if (builder != null) {
      return builder(context, source, width, height);
    }
    return const Icon(
      AleraIcons.viewImage,
      size: AleraTokens.iconLg,
      color: AleraTokens.foregroundMuted,
      semanticLabel: 'Image',
    );
  }

  Widget _buildCode(
    BuildContext context,
    String info,
    String code,
    bool closed,
  ) {
    // The language is the first word of the fence's info string.
    final language = info.trim().split(RegExp(r'\s')).first;
    // The parser keeps the newline before the closing fence, which would
    // otherwise render as an empty last line.
    final source = code.endsWith('\n')
        ? code.substring(0, code.length - 1)
        : code;
    final builder = widget.codeBuilder;
    if (builder != null) {
      return builder(context, language, source, closed);
    }
    return AleraCodeBlock(code: source, language: language);
  }
}
