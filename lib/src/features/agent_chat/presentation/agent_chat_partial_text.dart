import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Missing segments may contain the Markdown context for the loaded text.
class const AgentChatPartialText({
  super.key,
  required final String text,
  final bool muted = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (text.isNotEmpty)
        SelectableText(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: muted ? AleraTokens.foregroundMuted : AleraTokens.foreground,
          ),
        ),
      const AgentChatPartialMessageNote(),
    ],
  );
}

class const AgentChatPartialMessageNote({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: AleraTokens.space4),
    child: Text(
      'Only part of this message is loaded.',
      style: AleraTokens.labelMicroFaintStyle,
    ),
  );
}
