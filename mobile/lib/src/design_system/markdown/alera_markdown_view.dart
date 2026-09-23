import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

typedef AleraMarkdownImageBuilder = Widget Function(
  BuildContext context,
  String imageUrl,
  double? width,
  double? height,
);

/// Read-only Markdown in the same look as the desktop Markdown viewer.
///
/// Links and images are delegated to the caller, which owns the URI policy.
class const AleraMarkdownView({
  super.key,
  required final String data,
  required final AleraMarkdownImageBuilder imageBuilder,
  required final ValueChanged<String> onLinkTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bodyStyle =
        Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: AleraTokens.foreground, height: 1.45) ??
        const TextStyle(color: AleraTokens.foreground, height: 1.45);
    return SelectionArea(
      child: GptMarkdownTheme(
        gptThemeData: GptMarkdownThemeData(
          brightness: .dark,
          linkColor: AleraTokens.info,
          highlightColor: AleraTokens.accentSubtle,
          hrLineColor: AleraTokens.borderSubtle,
        ),
        child: DefaultTextStyle(
          style: bodyStyle,
          child: GptMarkdown(
            data,
            imageBuilder: imageBuilder,
            codeBuilder: _buildCodeBlock,
            onLinkTap: (url, _) => onLinkTap(url),
          ),
        ),
      ),
    );
  }
}

// Code scrolls sideways instead of wrapping: on a phone-width column a wrapped
// line is indistinguishable from two lines.
Widget _buildCodeBlock(
  BuildContext context,
  String language,
  String code,
  bool closed,
) {
  final theme = Theme.of(context);
  return DecoratedBox(
    decoration: BoxDecoration(
      color: AleraTokens.bg,
      border: Border.all(color: AleraTokens.borderSubtle),
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        if (language.trim().isNotEmpty) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space6,
            ),
            child: Text(
              language.trim(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          const Divider(height: 1, color: AleraTokens.borderSubtle),
        ],
        SingleChildScrollView(
          scrollDirection: .horizontal,
          padding: const EdgeInsets.all(AleraTokens.space8),
          child: Text(
            code,
            style: AleraTokens.monoStyle.copyWith(
              color: AleraTokens.foreground,
            ),
          ),
        ),
      ],
    ),
  );
}
