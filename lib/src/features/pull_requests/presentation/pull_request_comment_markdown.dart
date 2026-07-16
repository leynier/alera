import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class PullRequestCommentMarkdown extends StatelessWidget {
  const PullRequestCommentMarkdown({
    super.key,
    required this.body,
    required this.onOpenUrl,
  });

  final String body;
  final Future<void> Function(String url) onOpenUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle =
        theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foreground,
          height: 1.4,
        ) ??
        const TextStyle(color: AleraTokens.foreground, height: 1.4);
    return SelectionArea(
      child: GptMarkdownTheme(
        gptThemeData: GptMarkdownThemeData(
          brightness: Brightness.dark,
          h1: theme.textTheme.titleMedium,
          h2: theme.textTheme.titleSmall,
          h3: theme.textTheme.labelLarge,
          h4: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          h5: bodyStyle.copyWith(fontWeight: FontWeight.w600),
          h6: bodyStyle.copyWith(
            color: AleraTokens.foregroundMuted,
            fontWeight: FontWeight.w600,
          ),
          hrLineColor: AleraTokens.borderSubtle,
          hrLinePadding: const EdgeInsets.symmetric(
            vertical: AleraTokens.space4,
          ),
          linkColor: AleraTokens.info,
          linkHoverColor: AleraTokens.foreground,
          highlightColor: AleraTokens.accentSubtle,
          autoAddDividerLineAfterH1: false,
        ),
        child: DefaultTextStyle(
          style: bodyStyle,
          child: GptMarkdown(
            body,
            style: bodyStyle,
            codeBuilder: _buildCodeBlock,
            imageBuilder: buildPullRequestCommentImage,
            onLinkTap: (url, _) {
              if (isSupportedPullRequestCommentLinkUri(Uri.tryParse(url))) {
                unawaited(onOpenUrl(url));
              }
            },
          ),
        ),
      ),
    );
  }

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
            scrollDirection: Axis.horizontal,
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
}

bool isSupportedPullRequestCommentLinkUri(Uri? uri) {
  if (uri == null || uri.host.trim().isEmpty) {
    return false;
  }
  return switch (uri.scheme.toLowerCase()) {
    'http' || 'https' => true,
    _ => false,
  };
}

bool isSupportedPullRequestCommentImageUri(Uri? uri) {
  return uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.trim().isNotEmpty;
}

Widget buildPullRequestCommentImage(
  BuildContext context,
  String imageUrl,
  double? width,
  double? height,
) {
  final safeWidth = _limitImageDimension(width, AleraTokens.imageMaxWidth);
  final safeHeight = _limitImageDimension(height, AleraTokens.imageMaxHeight);
  if (!isSupportedPullRequestCommentImageUri(Uri.tryParse(imageUrl))) {
    return _PullRequestCommentImagePlaceholder(
      width: safeWidth,
      height: safeHeight,
    );
  }
  return ConstrainedBox(
    constraints: const BoxConstraints(
      maxWidth: AleraTokens.imageMaxWidth,
      maxHeight: AleraTokens.imageMaxHeight,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      child: Image.network(
        imageUrl,
        width: safeWidth,
        height: safeHeight,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _PullRequestCommentImagePlaceholder(
          width: safeWidth,
          height: safeHeight,
        ),
      ),
    ),
  );
}

double? _limitImageDimension(double? value, double maximum) {
  if (value == null || value <= 0) {
    return null;
  }
  return value > maximum ? maximum : value;
}

class _PullRequestCommentImagePlaceholder extends StatelessWidget {
  const _PullRequestCommentImagePlaceholder({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? AleraTokens.space48,
      height: height ?? AleraTokens.space48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        border: Border.all(color: AleraTokens.borderSubtle),
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      ),
      child: const Icon(
        AleraIcons.imageError,
        color: AleraTokens.foregroundMuted,
        size: 20,
      ),
    );
  }
}
