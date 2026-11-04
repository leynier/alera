import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_request_card.dart';
import 'package:flutter/material.dart';

/// A masked secret the agent asked for with `request_secret`
/// (`agentChatSecretRequestsV1`). The value goes to the host's secret
/// broker through `agentChat.secret.provide` and never into the chat; the
/// field is cleared once it is sent or the card leaves.
class AgentChatSecretCard extends StatefulWidget {
  const AgentChatSecretCard({
    super.key,
    required this.request,
    required this.enabled,
    required this.onRespond,
  });

  final AgentChatRequest request;
  final bool enabled;
  final AgentChatRespond onRespond;

  @override
  State<AgentChatSecretCard> createState() => _AgentChatSecretCardState();
}

class _AgentChatSecretCardState extends State<AgentChatSecretCard> {
  final TextEditingController _value = TextEditingController();
  bool _hasValue = false;
  bool _sending = false;

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

  bool get _active => widget.enabled && !_sending;

  Future<void> _provide(String? value) async {
    if (!_active) return;
    setState(() => _sending = true);
    _value.clear();
    try {
      await widget.onRespond(widget.request, AgentChatSecretResponse(value));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.request;
    final detail = request.detail?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.warning),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: AleraTokens.space8,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                AleraIcons.notifications,
                size: AleraTokens.space16,
                color: AleraTokens.warning,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  request.title ?? 'Secret Requested',
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          if (detail.isNotEmpty) Text(detail),
          TextField(
            key: const ValueKey<String>('agent-chat-secret-field'),
            controller: _value,
            enabled: _active,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            maxLines: 1,
            decoration: InputDecoration(
              hintText: request.placeholder ?? 'Secret value',
            ),
            onSubmitted: (value) {
              if (value.isNotEmpty) _provide(value);
            },
          ),
          Text(
            'Only the host stores this value. The agent gets a private file '
            'or a one-use reference, never the text.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          Wrap(
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space4,
            children: <Widget>[
              FilledButton(
                onPressed: _active && _hasValue
                    ? () => _provide(_value.text)
                    : null,
                child: const Text('Save Secret'),
              ),
              OutlinedButton(
                onPressed: _active ? () => _provide(null) : null,
                child: const Text('Decline'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
