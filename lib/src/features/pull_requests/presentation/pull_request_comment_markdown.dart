import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_text_selection_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class const PullRequestCommentMarkdown({
  super.key,
  required final String body,
  required final Future<void> Function(String url) onOpenUrl,
  final bool taskListEditable = false,
  final bool taskListSaving = false,
  final Future<void> Function(int itemIndex)? onTaskListItemToggle,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle =
        theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foreground,
          height: 1.4,
        ) ??
        const TextStyle(color: AleraTokens.foreground, height: 1.4);
    final components = <MarkdownComponent>[
      for (final component in MarkdownComponent.globalComponents)
        if (component is! CheckBoxMd) component,
      _PullRequestTaskCheckboxMd(
        enabled:
            taskListEditable && !taskListSaving && onTaskListItemToggle != null,
        onToggle: onTaskListItemToggle,
      ),
    ];
    return SelectionArea(
      contextMenuBuilder: AleraTextSelectionToolbar.selectableRegion,
      child: GptMarkdownTheme(
        gptThemeData: GptMarkdownThemeData(
          brightness: .dark,
          h1: theme.textTheme.titleMedium,
          h2: theme.textTheme.titleSmall,
          h3: theme.textTheme.labelLarge,
          h4: theme.textTheme.bodyMedium?.copyWith(fontWeight: .w600),
          h5: bodyStyle.copyWith(fontWeight: .w600),
          h6: bodyStyle.copyWith(
            color: AleraTokens.foregroundMuted,
            fontWeight: .w600,
          ),
          hrLineColor: AleraTokens.borderSubtle,
          hrLinePadding: const .symmetric(vertical: AleraTokens.space4),
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
            components: components,
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
}

class _PullRequestTaskCheckboxMd({
  required final bool enabled,
  required final Future<void> Function(int itemIndex)? onToggle,
}) extends BlockMd {
  var _nextItemIndex = 0;

  @override
  String get expString => r"\[((?:x|X| ))\][ \t]+(\S[^\n]*?)$";

  @override
  Widget build(BuildContext context, String text, GptMarkdownConfig config) {
    final match = exp.firstMatch(text.trim());
    if (match == null) {
      return const SizedBox.shrink();
    }
    final itemIndex = _nextItemIndex++;
    final checked = match.group(1)!.toLowerCase() == 'x';
    return Row(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: <Widget>[
        AleraCheckbox(
          value: checked,
          enabled: enabled,
          onChanged: (_) {
            final callback = onToggle;
            if (callback != null) {
              unawaited(callback(itemIndex));
            }
          },
        ),
        const SizedBox(width: AleraTokens.space4),
        Flexible(
          child: MdWidget(context, match.group(2)!, false, config: config),
        ),
      ],
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
        fit: .contain,
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

class const _PullRequestCommentImagePlaceholder({
  final double? width,
  final double? height,
}) extends StatelessWidget {
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
