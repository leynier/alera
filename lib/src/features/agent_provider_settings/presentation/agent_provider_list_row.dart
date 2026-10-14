import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_provider_icon.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_status.dart';
import 'package:flutter/material.dart';

/// Status tone: green only for a verified sign-in, warning when a person has
/// to act, error when the runtime cannot start it, neutral otherwise.
AleraBadgeTone agentProviderStatusTone(AgentProviderStatusKind kind) =>
    switch (kind) {
      .ready => .success,
      .signInNeeded || .notInstalled || .setupRequired => .attention,
      .error => .error,
      .checking => .info,
      .unknownSignIn || .off => .neutral,
    };

class const AgentProviderStatusBadge({
  super.key,
  required final AgentProviderStatus status,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Tooltip(
    message: status.detail,
    child: AleraBadge(
      label: status.label,
      tone: agentProviderStatusTone(status.kind),
    ),
  );
}

/// One provider instance in the Providers list: its mark, label, version and
/// status, and the switch that offers it to Agent Chat.
class const AgentProviderListRow({
  super.key,
  required final String provider,
  required final String label,
  required final AgentProviderStatus status,
  required final bool selected,
  required final bool enabled,
  required final VoidCallback onTap,
  final String? version,
  final bool isDefault = false,
  final bool unsaved = false,
  final ValueChanged<bool>? onEnabledChanged,

  /// Why the switch is disabled when [onEnabledChanged] is null.
  final String? enabledLockedReason,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = !enabled;
    final caption = <String>[
      ?version,
      if (isDefault) 'Default',
      if (unsaved) 'Not saved',
    ].join('  ·  ');
    return AleraActiveRail(
      active: selected,
      child: Material(
        color: selected ? AleraActiveRail.selectedColor : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space12,
              vertical: AleraTokens.space8,
            ),
            // The status line gets the row's full width under the name, and
            // wraps, so a narrow list column never clips the status label.
            child: Column(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AgentChatProviderIcon(
                      provider: provider,
                      size: AleraTokens.iconLg,
                      color: muted
                          ? AleraTokens.foregroundFaint
                          : selected
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: muted
                              ? AleraTokens.foregroundMuted
                              : AleraTokens.foreground,
                          fontWeight: .w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Semantics(
                      label: enabled
                          ? 'Turn Off $label For Agent Chat'
                          : 'Turn On $label For Agent Chat',
                      child: Tooltip(
                        message: onEnabledChanged == null
                            ? enabledLockedReason ??
                                  'This provider cannot be turned on or off '
                                      'right now.'
                            : enabled
                            ? 'Offered for new chats'
                            : 'Not offered for new chats',
                        child: Switch(
                          value: enabled,
                          onChanged: onEnabledChanged,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: AleraTokens.iconLg + AleraTokens.space8,
                  ),
                  child: Wrap(
                    spacing: AleraTokens.space6,
                    runSpacing: AleraTokens.space4,
                    crossAxisAlignment: .center,
                    children: <Widget>[
                      AgentProviderStatusBadge(status: status),
                      if (caption.isNotEmpty)
                        Text(
                          caption,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
