import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// A masked secret the agent asked for with `request_secret`
/// (`agentChatSecretRequestsV1`). The value goes to the host's secret
/// broker through `agentChat.secret.provide` and never into the chat; the
/// field is cleared once the card leaves, and nothing keeps a draft of it.
class AgentChatSecretCard extends StatefulWidget {
  const AgentChatSecretCard({
    super.key,
    required this.request,
    required this.responding,
    required this.enabled,
    required this.onProvide,
    this.takeFocus = false,
  });

  final AgentChatRequest request;
  final bool responding;
  final bool enabled;

  /// Saves the value, or declines with null.
  final ValueChanged<String?> onProvide;
  final bool takeFocus;

  @override
  State<AgentChatSecretCard> createState() => _AgentChatSecretCardState();
}

class _AgentChatSecretCardState extends State<AgentChatSecretCard> {
  final TextEditingController _value = TextEditingController();
  bool _hasValue = false;

  @override
  void initState() {
    super.initState();
    _value.addListener(() {
      final hasValue = _value.text.isNotEmpty;
      if (hasValue != _hasValue) setState(() => _hasValue = hasValue);
    });
  }

  @override
  void dispose() {
    _value
      ..clear()
      ..dispose();
    super.dispose();
  }

  void _save() {
    if (!_hasValue || !_active) return;
    final value = _value.text;
    _value.clear();
    widget.onProvide(value);
  }

  bool get _active => widget.enabled && !widget.responding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.request;
    final detail = agentChatJsonString(request.detail);
    return Material(
      color: AleraTokens.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        side: const BorderSide(color: AleraTokens.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space12),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: AleraTokens.space8,
          children: <Widget>[
            Text(
              agentChatJsonString(request.title) ?? 'Secret Requested',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: .w600),
            ),
            if (detail != null)
              SelectableText(detail, style: theme.textTheme.bodyMedium),
            TextField(
              key: const ValueKey<String>('agent-chat-secret-field'),
              controller: _value,
              autofocus: widget.takeFocus,
              enabled: _active,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              maxLines: 1,
              decoration: InputDecoration(
                isDense: true,
                hintText: request.placeholder ?? 'Secret value',
              ),
              onSubmitted: (_) => _save(),
            ),
            Text(
              'Only the host stores this value. The agent gets a private '
              'file or a one-use reference, never the text.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            Wrap(
              spacing: AleraTokens.space8,
              runSpacing: AleraTokens.space8,
              children: <Widget>[
                FilledButton(
                  onPressed: _active && _hasValue ? _save : null,
                  child: const Text('Save Secret'),
                ),
                TextButton(
                  onPressed: _active ? () => widget.onProvide(null) : null,
                  child: const Text('Decline'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
