import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_provider_identity.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';

/// The divider above a turn that carried the transcript into a fresh
/// provider session, as the desktop draws it: "Context Handoff" with the
/// provider it came from and the one it went to, in the error tone when the
/// handoff never reached the provider.
class const AgentChatHandoffDivider({
  super.key,
  required final AgentChatHandoff handoff,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = handoff.failed
        ? AleraTokens.error
        : AleraTokens.foregroundMuted;
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: color);
    final from = handoff.from;
    final label = agentChatHandoffLabel(handoff);
    final semantics = from == null
        ? '$label to ${_endpointLabel(handoff.to)}'
        : '$label from ${_endpointLabel(from)} to ${_endpointLabel(handoff.to)}';
    return Semantics(
      container: true,
      label: semantics,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AleraTokens.space12),
          child: Row(
            children: <Widget>[
              const Expanded(child: Divider(color: AleraTokens.borderSubtle)),
              const SizedBox(width: AleraTokens.space12),
              Flexible(
                flex: 4,
                child: Wrap(
                  alignment: .center,
                  crossAxisAlignment: .center,
                  spacing: AleraTokens.space6,
                  runSpacing: AleraTokens.space4,
                  children: <Widget>[
                    if (handoff.failed)
                      Icon(
                        AleraIcons.warning,
                        size: AleraTokens.iconSm,
                        color: color,
                      ),
                    Text(label, style: style),
                    if (from != null) ...<Widget>[
                      _Endpoint(endpoint: from, style: style),
                      const Icon(
                        AleraIcons.chevronRight,
                        size: AleraTokens.iconSm,
                        color: AleraTokens.foregroundFaint,
                      ),
                    ],
                    _Endpoint(endpoint: handoff.to, style: style),
                  ],
                ),
              ),
              const SizedBox(width: AleraTokens.space12),
              const Expanded(child: Divider(color: AleraTokens.borderSubtle)),
            ],
          ),
        ),
      ),
    );
  }
}

String _endpointLabel(AgentChatHandoffEndpoint endpoint) =>
    endpoint.model ?? _providerLabel(endpoint.provider);

String _providerLabel(String provider) =>
    switch (agentChatProviderName(provider)) {
      'the agent' => provider,
      final name => name,
    };

class const _Endpoint({
  required final AgentChatHandoffEndpoint endpoint,
  required final TextStyle? style,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        AgentIdentityIcon(
          agentType: agentChatAgentType(endpoint.provider),
          size: AleraTokens.iconSm,
          showTooltip: false,
        ),
        const SizedBox(width: AleraTokens.space4),
        Flexible(
          child: Text(
            _endpointLabel(endpoint),
            maxLines: 1,
            overflow: .ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}
