import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Missing segments may contain the Markdown context for the loaded text.
class const AgentChatPartialText({super.key, required final String text})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: <Widget>[
      if (text.isNotEmpty)
        SelectableText(text, style: Theme.of(context).textTheme.bodyMedium),
      const AgentChatPartialMessageNote(),
    ],
  );
}

class const AgentChatPartialMessageNote({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AleraTokens.space4),
    child: Text(
      'Only part of this message is loaded.',
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: AleraTokens.foregroundFaint),
    ),
  );
}
