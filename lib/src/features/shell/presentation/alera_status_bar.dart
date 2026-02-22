import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter/material.dart';

class AleraStatusBar extends StatelessWidget {
  const AleraStatusBar({
    super.key,
    required this.state,
    required this.rawLogExpanded,
    required this.onToggleRawLog,
    required this.onCopyRawLog,
    required this.canCopyRawLog,
  });

  final SessionState state;
  final bool rawLogExpanded;
  final VoidCallback onToggleRawLog;
  final VoidCallback onCopyRawLog;
  final bool canCopyRawLog;

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
          if (state.statusHeader != null &&
              state.statusHeader!.trim().isNotEmpty) ...<Widget>[
            _separator(),
            _StatusChip(
              label: state.statusHeader!,
              color: AleraTokens.foregroundMuted,
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
          const SizedBox(width: AleraTokens.space8),
          Tooltip(
            message: canCopyRawLog ? 'copy raw logs' : 'no raw logs',
            child: InkWell(
              key: const ValueKey<String>('copy-raw-log-button'),
              onTap: canCopyRawLog ? onCopyRawLog : null,
              mouseCursor: canCopyRawLog
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              child: Padding(
                padding: const EdgeInsets.all(AleraTokens.space4),
                child: Icon(
                  Icons.content_copy,
                  size: 14,
                  color: canCopyRawLog
                      ? AleraTokens.foreground
                      : AleraTokens.foregroundFaint,
                ),
              ),
            ),
          ),
          const SizedBox(width: AleraTokens.space6),
          Tooltip(
            message: rawLogExpanded ? 'hide raw log' : 'show raw log',
            child: InkWell(
              key: const ValueKey<String>('toggle-raw-log-button'),
              onTap: onToggleRawLog,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              child: Padding(
                padding: const EdgeInsets.all(AleraTokens.space4),
                child: Icon(
                  Icons.terminal,
                  size: 14,
                  color: rawLogExpanded
                      ? AleraTokens.foreground
                      : AleraTokens.foregroundFaint,
                ),
              ),
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
