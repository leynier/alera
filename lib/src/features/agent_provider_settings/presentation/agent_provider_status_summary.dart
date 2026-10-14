import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/design_system/surfaces/alera_command_line.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_provider_icon.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_status.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_list_row.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// The detail header: the instance's identity and verified status, then the
/// host-verified setup commands it offers. [setupHostLabel] names the Remote
/// Host those commands run on; null means This Device.
class const AgentProviderStatusSummary({
  super.key,
  required final String provider,
  required final String providerInstanceId,
  required final String title,
  required final AgentProviderStatus status,
  required final DateTime now,
  final AgentChatProviderInstance? catalog,
  final bool canRunSetup = true,
  final String? setupHostLabel,
  final String? setupUnavailableReason,
  final ValueChanged<AgentChatProviderSetupCommand>? onRunSetup,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = catalog;
    final setup = row?.setup ?? const <AgentChatProviderSetupCommand>[];
    final where = setupHostLabel == null ? '' : ' on $setupHostLabel';
    final caption = providerInstanceId == provider
        ? 'Built-in  ·  $provider'
        : '$providerInstanceId  ·  $provider';
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            AgentChatProviderIcon(
              provider: provider,
              size: AleraTokens.iconXxl,
              color: AleraTokens.foreground,
            ),
            const SizedBox(width: AleraTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AleraTokens.space2),
                  SelectableText(
                    caption,
                    maxLines: 1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ],
              ),
            ),
            AgentProviderStatusBadge(status: status),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        AleraSettingsGroup(
          title: 'Setup',
          description: status.detail,
          children: <Widget>[
            _Fact(
              label: 'Installation',
              value: _installation(row),
              state: switch (row?.installed) {
                true => _FactState.good,
                false => _FactState.attention,
                null => _FactState.unknown,
              },
            ),
            _Fact(
              label: 'Sign-In',
              value: _signIn(row, now),
              state: switch (row?.auth) {
                final auth? when auth.verified && auth.status == .signedIn =>
                  _FactState.good,
                final auth? when auth.verified => _FactState.attention,
                _ => _FactState.unknown,
              },
            ),
            if (setup.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space16),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    Wrap(
                      spacing: AleraTokens.space8,
                      runSpacing: AleraTokens.space8,
                      children: <Widget>[
                        for (final command in setup)
                          Tooltip(
                            message: canRunSetup
                                ? 'Runs the verified ${command.label} '
                                      'command for this instance in a '
                                      'terminal$where, then checks again.'
                                : setupUnavailableReason ?? '',
                            child: _SetupButton(
                              command: command,
                              onPressed: canRunSetup && onRunSetup != null
                                  ? () => onRunSetup!(command)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                    if (canRunSetup && setupHostLabel != null) ...<Widget>[
                      const SizedBox(height: AleraTokens.space12),
                      Text(
                        'Setup runs in a terminal on $setupHostLabel.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    ],
                    if (!canRunSetup) ...<Widget>[
                      const SizedBox(height: AleraTokens.space12),
                      Text(
                        setupUnavailableReason ??
                            'Run these commands on the host itself.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                      for (final command in setup) ...<Widget>[
                        const SizedBox(height: AleraTokens.space6),
                        AleraCommandLine(command: command.command),
                      ],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _installation(AgentChatProviderInstance? row) {
    if (row == null) {
      return 'Not reported by this host';
    }
    return switch (row.installed) {
      true =>
        row.version == null ? 'Installed' : 'Installed  ·  ${row.version}',
      false => 'Not installed',
      null => row.version ?? 'Not reported by this host',
    };
  }

  static String _signIn(AgentChatProviderInstance? row, DateTime now) {
    final auth = row?.auth;
    if (auth == null || !auth.verified) {
      return 'Not verified';
    }
    final checked = agentProviderCheckedLabel(auth.checkedAt, now);
    final state = auth.status == .signedIn ? 'Signed in' : 'Signed out';
    final account = auth.label;
    return account == null
        ? '$state  ·  $checked'
        : '$state as $account  ·  $checked';
  }
}

enum _FactState { good, attention, unknown }

class const _Fact({
  required final String label,
  required final String value,
  required final _FactState state,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space16,
        vertical: AleraTokens.space12,
      ),
      child: Row(
        children: <Widget>[
          AleraStatusDot(
            active: state != _FactState.unknown,
            color: switch (state) {
              _FactState.good => AleraTokens.success,
              _FactState.attention => AleraTokens.warning,
              _FactState.unknown => AleraTokens.foregroundFaint,
            },
          ),
          const SizedBox(width: AleraTokens.space8),
          SizedBox(
            width: AleraTokens.space48 * 2,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foreground,
                fontWeight: .w500,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class const _SetupButton({
  required final AgentChatProviderSetupCommand command,
  required final VoidCallback? onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Sign In is what unblocks a chat, so it is the primary action; Install
    // and Update stay secondary.
    final label = Text(command.label);
    return command.action == 'signIn'
        ? FilledButton(onPressed: onPressed, child: label)
        : OutlinedButton(onPressed: onPressed, child: label);
  }
}
