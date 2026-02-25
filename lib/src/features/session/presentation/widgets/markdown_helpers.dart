import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

bool isMarkdownRenderSafe(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalized.trim().isEmpty) {
    return false;
  }
  if (!_hasBalancedCodeFences(normalized)) {
    return false;
  }
  if (!_hasBalancedInlineBackticksOutsideFences(normalized)) {
    return false;
  }
  try {
    final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    document.parseLines(normalized.split('\n'));
    return true;
  } catch (_) {
    return false;
  }
}

bool _hasBalancedCodeFences(String text) {
  var count = 0;
  var index = 0;
  while (true) {
    index = text.indexOf('```', index);
    if (index == -1) {
      break;
    }
    count += 1;
    index += 3;
  }
  return count.isEven;
}

bool _hasBalancedInlineBackticksOutsideFences(String text) {
  var inFence = false;
  var inlineBackticks = 0;
  for (var i = 0; i < text.length; i++) {
    if (i + 2 < text.length &&
        text.codeUnitAt(i) == 0x60 &&
        text.codeUnitAt(i + 1) == 0x60 &&
        text.codeUnitAt(i + 2) == 0x60) {
      inFence = !inFence;
      i += 2;
      continue;
    }
    if (!inFence && text.codeUnitAt(i) == 0x60) {
      inlineBackticks += 1;
    }
  }
  return !inFence && inlineBackticks.isEven;
}

@visibleForTesting
bool Function() copyMouseConnectionDetector = () =>
    RendererBinding.instance.mouseTracker.mouseIsConnected;

bool mouseIsConnected() => copyMouseConnectionDetector();

class CodeBlockBuilder extends MarkdownElementBuilder {
  CodeBlockBuilder(this.context);

  final BuildContext context;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    if (text.trim().isEmpty) {
      return null;
    }
    return CopyableCodeBlock(code: text);
  }
}

class CopyableCodeBlock extends StatelessWidget {
  const CopyableCodeBlock({super.key, required this.code});

  final String code;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Code copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AleraTokens.space8),
      decoration: BoxDecoration(
        color: AleraTokens.bg,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space4,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AleraTokens.borderSubtle),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Code',
                    style: TextStyle(
                      color: AleraTokens.foregroundFaint,
                      fontSize: 10,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _copy(context),
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AleraTokens.space6,
                      vertical: AleraTokens.space2,
                    ),
                    child: Text(
                      'Copy',
                      style: TextStyle(
                        color: AleraTokens.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: SelectableText(
              code,
              style: AleraTokens.monoStyle.copyWith(
                color: AleraTokens.foreground,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MessageActionButtons extends StatelessWidget {
  const MessageActionButtons({
    super.key,
    required this.alignLeft,
    required this.copyKey,
    required this.copyText,
    required this.copiedLabel,
    required this.toggleKey,
    required this.markdownEnabled,
    required this.onToggleMarkdown,
  });

  final bool alignLeft;
  final ValueKey<String> copyKey;
  final String copyText;
  final String copiedLabel;
  final ValueKey<String> toggleKey;
  final bool markdownEnabled;
  final ValueChanged<bool> onToggleMarkdown;

  @override
  Widget build(BuildContext context) {
    final copy = MessageCopyButton(
      key: copyKey,
      copyText: copyText,
      copiedLabel: copiedLabel,
    );
    final markdownToggle = MessageMarkdownToggleButton(
      key: toggleKey,
      markdownEnabled: markdownEnabled,
      onChanged: onToggleMarkdown,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: alignLeft
          ? <Widget>[
              copy,
              const SizedBox(width: AleraTokens.space2),
              markdownToggle,
            ]
          : <Widget>[
              markdownToggle,
              const SizedBox(width: AleraTokens.space2),
              copy,
            ],
    );
  }
}

class MessageCopyButton extends StatelessWidget {
  const MessageCopyButton({
    super.key,
    required this.copyText,
    required this.copiedLabel,
  });

  final String copyText;
  final String copiedLabel;

  Future<void> _copy(BuildContext context) async {
    if (copyText.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: copyText));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(copiedLabel)));
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _copy(context),
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      child: const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AleraTokens.space4,
          vertical: AleraTokens.space2,
        ),
        child: Icon(
          Icons.content_copy,
          size: 12,
          color: AleraTokens.foregroundFaint,
        ),
      ),
    );
  }
}

class MessageMarkdownToggleButton extends StatelessWidget {
  const MessageMarkdownToggleButton({
    super.key,
    required this.markdownEnabled,
    required this.onChanged,
  });

  final bool markdownEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: markdownEnabled ? 'Markdown ON' : 'Markdown OFF',
      child: InkWell(
        onTap: () => onChanged(!markdownEnabled),
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AleraTokens.space4,
            vertical: AleraTokens.space2,
          ),
          child: Icon(Icons.code, size: 13, color: AleraTokens.foregroundFaint),
        ),
      ),
    );
  }
}
