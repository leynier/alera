import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_provider_icon.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// The divider above a turn that carried the transcript into a fresh
/// provider session: "Context Handoff" with the provider it came from and
/// the one it went to. A handoff that never reached the provider reads as
/// failed, in the error tone.
class const AgentChatHandoffDivider({
  super.key,
  required final AgentChatHandoff handoff,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = handoff.failed
        ? AleraTokens.error
        : AleraTokens.foregroundMuted;
    final style = theme.textTheme.labelSmall?.copyWith(color: color);
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
              const Expanded(child: _Rule()),
              const SizedBox(width: AleraTokens.space12),
              Flexible(
                flex: 4,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
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
                      Icon(
                        AleraIcons.forward,
                        size: AleraTokens.iconSm,
                        color: AleraTokens.foregroundFaint,
                      ),
                    ],
                    _Endpoint(endpoint: handoff.to, style: style),
                  ],
                ),
              ),
              const SizedBox(width: AleraTokens.space12),
              const Expanded(child: _Rule()),
            ],
          ),
        ),
      ),
    );
  }
}

String _endpointLabel(AgentChatHandoffEndpoint endpoint) =>
    endpoint.model ?? agentChatProviderFallbackLabel(endpoint.provider);

class const _Endpoint({
  required final AgentChatHandoffEndpoint endpoint,
  required final TextStyle? style,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AgentChatProviderIcon(provider: endpoint.provider),
        const SizedBox(width: AleraTokens.space4),
        Flexible(
          child: Text(
            _endpointLabel(endpoint),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }
}

class const _Rule() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Divider(
    height: AleraTokens.dividerExtent,
    color: AleraTokens.borderSubtle,
  );
}
