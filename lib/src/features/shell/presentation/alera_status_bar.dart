import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/presentation/widgets/diff_viewer.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter/material.dart';

class AleraStatusBar extends StatelessWidget {
  const AleraStatusBar({
    super.key,
    required this.connectionState,
    required this.runningTurnCount,
    this.statusHeader,
    this.lastTurnDiff,
    this.workspacePath,
    required this.rawLogExpanded,
    required this.onToggleRawLog,
    required this.onCopyRawLog,
    required this.canCopyRawLog,
  });

  final AppServerConnectionState connectionState;
  final int runningTurnCount;
  final String? statusHeader;
  final String? lastTurnDiff;
  final String? workspacePath;
  final bool rawLogExpanded;
  final VoidCallback onToggleRawLog;
  final VoidCallback onCopyRawLog;
  final bool canCopyRawLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = statusHeader;
    final diff = lastTurnDiff;

    return Container(
      height: AleraTokens.statusBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: <Widget>[
          _StatusChip(
            label: _connectionLabel(connectionState),
            color: _connectionColor(connectionState),
          ),
          if (runningTurnCount > 0) ...<Widget>[
            _separator(),
            _StatusChip(
              label: 'Running: $runningTurnCount',
              color: AleraTokens.accent,
            ),
          ],
          if (header != null && header.trim().isNotEmpty) ...<Widget>[
            _separator(),
            _StatusChip(
              label: header,
              color: AleraTokens.foregroundMuted,
            ),
          ],
          const Spacer(),
          if (diff != null) ...<Widget>[
            Tooltip(
              message: 'View file changes',
              child: InkWell(
                onTap: () => DiffViewerDialog.show(context, diff),
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                child: const Padding(
                  padding: EdgeInsets.all(AleraTokens.space4),
                  child: Icon(
                    Icons.difference_outlined,
                    size: 14,
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AleraTokens.space6),
          ],
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
            message: canCopyRawLog ? 'Copy raw logs' : 'No raw logs',
            child: InkWell(
              key: const ValueKey<String>('copy-raw-log-button'),
              onTap: canCopyRawLog ? onCopyRawLog : null,
              mouseCursor: canCopyRawLog
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
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
            message: rawLogExpanded ? 'Hide raw log' : 'Show raw log',
            child: InkWell(
              key: const ValueKey<String>('toggle-raw-log-button'),
              onTap: onToggleRawLog,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
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

  String _connectionLabel(AppServerConnectionState state) {
    return switch (state) {
      AppServerConnectionState.connected => 'Connected',
      AppServerConnectionState.starting => 'Starting',
      AppServerConnectionState.error => 'Error',
      AppServerConnectionState.disconnected => 'Offline',
    };
  }

  Color _connectionColor(AppServerConnectionState state) {
    return switch (state) {
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
