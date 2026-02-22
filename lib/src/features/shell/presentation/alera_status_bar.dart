import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter/material.dart';

class AleraStatusBar extends StatelessWidget {
  const AleraStatusBar({super.key, required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = state.activeSession;
    final workspacePath = session?.workspacePath ?? state.selectedWorkspacePath;
    return Container(
      height: AleraTokens.statusBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: <Widget>[
          _StatusChip(label: _connectionLabel(), color: _connectionColor()),
          if (state.runningTurnCount > 0) ...<Widget>[
            _separator(),
            _StatusChip(
              label: '${state.runningTurnCount} running',
              color: AleraTokens.accent,
            ),
          ],
          const Spacer(),
          Text(
            workspacePath ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AleraTokens.monoStyle.copyWith(
              fontSize: 10,
              color: AleraTokens.foregroundFaint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _separator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AleraTokens.space8),
      child: SizedBox(
        height: 12,
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: AleraTokens.border,
        ),
      ),
    );
  }

  String _connectionLabel() {
    return switch (state.connectionState) {
      AppServerConnectionState.connected => 'connected',
      AppServerConnectionState.starting => 'starting',
      AppServerConnectionState.error => 'error',
      AppServerConnectionState.disconnected => 'offline',
    };
  }

  Color _connectionColor() {
    return switch (state.connectionState) {
      AppServerConnectionState.connected => AleraTokens.success,
      AppServerConnectionState.starting => AleraTokens.accent,
      AppServerConnectionState.error => AleraTokens.error,
      AppServerConnectionState.disconnected => AleraTokens.foregroundMuted,
    };
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: AleraTokens.space4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}
