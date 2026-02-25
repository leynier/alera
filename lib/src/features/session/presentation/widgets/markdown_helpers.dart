import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_streaming_text_markdown/flutter_streaming_text_markdown.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

@visibleForTesting
bool Function() copyMouseConnectionDetector = () =>
    RendererBinding.instance.mouseTracker.mouseIsConnected;

bool mouseIsConnected() => copyMouseConnectionDetector();

Widget buildMarkdownContent({
  required BuildContext context,
  required String text,
  required bool markdownEnabled,
  required TextStyle? textStyle,
  TextStyle? markdownStyle,
  TextAlign? textAlign,
  bool useStreaming = true,
}) {
  if (!markdownEnabled) {
    return Text(text, style: textStyle, textAlign: textAlign);
  }
  if (!useStreaming) {
    return GptMarkdown(
      text,
      style: markdownStyle ?? textStyle,
      textAlign: textAlign,
      textDirection: Directionality.of(context),
    );
  }
  return StreamingText(
    text: text,
    style: textStyle,
    markdownEnabled: true,
    markdownStyleSheet: markdownStyle ?? textStyle,
    animationsEnabled: false,
    fadeInEnabled: false,
    showCursor: false,
    selectable: false,
    textAlign: textAlign,
  );
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
