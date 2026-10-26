import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_availability.dart';
import 'package:flutter/material.dart';

/// Why the chat cannot take input right now, and the one action that helps.
/// Nothing here navigates: the person stays on the chat they opened.
class const AgentChatStatusBanner({
  super.key,
  required final AgentChatAvailability availability,
  required final VoidCallback onRetry,
  final VoidCallback? onReopen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => switch (availability) {
    AgentChatAvailability.live => const SizedBox.shrink(),
    AgentChatAvailability.reconnecting => const _Banner(
      icon: AleraIcons.sync,
      tone: AleraTokens.foregroundMuted,
      message: 'Reconnecting to the host. The chat keeps running there.',
      busy: true,
    ),
    AgentChatAvailability.offline => _Banner(
      icon: AleraIcons.cloudOff,
      tone: AleraTokens.warning,
      message: 'The host is not reachable. Showing the last copy of this chat.',
      action: TextButton(onPressed: onRetry, child: const Text('Retry')),
    ),
    AgentChatAvailability.readOnly => _Banner(
      icon: AleraIcons.archive,
      tone: AleraTokens.foregroundMuted,
      message: 'This chat is archived. Its history is kept on the host.',
      action: onReopen == null
          ? null
          : TextButton(onPressed: onReopen, child: const Text('Reopen')),
    ),
  };
}

/// The provider session stopped and the runtime knows a way back. Sending a
/// message also restarts it, so the buttons are a shortcut, not a gate. An
/// agent that is missing or signed out on the host is fixed in Provider
/// Settings, which this offers instead of guessing at a restart.
class const AgentChatRecoveryBanner({
  super.key,
  required final AgentChatRecovery recovery,
  required final bool enabled,
  required final ValueChanged<AgentChatRecoverMode> onRecover,
  final VoidCallback? onOpenProviderSettings,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final needsSettings =
        recovery.kind == AgentChatRecoveryKind.providerMissing ||
        recovery.kind == AgentChatRecoveryKind.authRequired;
    return _Banner(
      icon: AleraIcons.warning,
      tone: AleraTokens.warning,
      message: recovery.message,
      clampMessage: true,
      action: Wrap(
        spacing: AleraTokens.space4,
        children: <Widget>[
          if (needsSettings && onOpenProviderSettings != null)
            TextButton(
              onPressed: onOpenProviderSettings,
              child: const Text(agentChatOpenProviderSettingsLabel),
            ),
          if (recovery.canResume)
            TextButton(
              onPressed: enabled ? () => onRecover(.resume) : null,
              child: const Text('Resume Session'),
            ),
          if (recovery.canRestart)
            TextButton(
              onPressed: enabled ? () => onRecover(.restart) : null,
              child: const Text('Start New Session'),
            ),
        ],
      ),
    );
  }
}

/// The chat's agent cannot run on the host right now, or there is none.
/// Send waits; Provider Settings is where it gets fixed.
class const AgentChatProviderNotice({
  super.key,
  required final String message,
  final VoidCallback? onOpenProviderSettings,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _Banner(
    icon: AleraIcons.agent,
    tone: AleraTokens.warning,
    message: message,
    clampMessage: true,
    action: onOpenProviderSettings == null
        ? null
        : TextButton(
            onPressed: onOpenProviderSettings,
            child: const Text(agentChatOpenProviderSettingsLabel),
          ),
  );
}

class const _Banner({
  required final IconData icon,
  required final Color tone,
  required final String message,
  final Widget? action,
  final bool busy = false,
  final bool clampMessage = false,
}) extends StatefulWidget {
  @override
  State<_Banner> createState() => _BannerState();
}

/// Errors clamp to three lines; tapping the text shows the rest.
class _BannerState extends State<_Banner> {
  bool _full = false;

  IconData get icon => widget.icon;
  Color get tone => widget.tone;
  String get message => widget.message;
  Widget? get action => widget.action;
  bool get busy => widget.busy;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Color.alphaBlend(
      tone.withValues(alpha: AleraTokens.statusTintAlpha),
      AleraTokens.surfaceVariant,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space16,
        vertical: AleraTokens.space4,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AleraTokens.minTapTarget),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (busy)
                  const SizedBox.square(
                    dimension: AleraTokens.space16,
                    child: CircularProgressIndicator(
                      strokeWidth: AleraTokens.strokeSm,
                    ),
                  )
                else
                  Icon(icon, size: AleraTokens.space16, color: tone),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: GestureDetector(
                    onTap: widget.clampMessage
                        ? () => setState(() => _full = !_full)
                        : null,
                    child: Text(
                      message,
                      maxLines: widget.clampMessage && !_full ? 3 : null,
                      overflow: widget.clampMessage && !_full
                          ? .ellipsis
                          : null,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AleraTokens.foreground),
                    ),
                  ),
                ),
              ],
            ),
            if (action case final action?)
              Align(alignment: Alignment.centerRight, child: action),
          ],
        ),
      ),
    ),
  );
}
