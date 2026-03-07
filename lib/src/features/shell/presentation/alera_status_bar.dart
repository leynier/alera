import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/features/session/presentation/widgets/diff_viewer.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:alera/src/shared/utils/format_utils.dart';
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
              label: 'Running: ${state.runningTurnCount}',
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
          if (_contextUsedTokens != null) ...<Widget>[
            _separator(),
            _ContextChip(
              usedTokens: _contextUsedTokens!,
              windowTokens: contextWindowForModel(state.activeModelId),
            ),
          ],
          const Spacer(),
          if (state.lastTurnDiff != null) ...<Widget>[
            Tooltip(
              message: 'View file changes',
              child: InkWell(
                onTap: () =>
                    DiffViewerDialog.show(context, state.lastTurnDiff!),
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

  int? get _contextUsedTokens {
    final v = state.turnRuntimeMetrics['totalTokens'];
    if (v is int) return v;
    return null;
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
      AppServerConnectionState.connected => 'Connected',
      AppServerConnectionState.starting => 'Starting',
      AppServerConnectionState.error => 'Error',
      AppServerConnectionState.disconnected => 'Offline',
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

class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.usedTokens, required this.windowTokens});

  final int usedTokens;
  final int windowTokens;

  double get _fraction => (usedTokens / windowTokens).clamp(0.0, 1.0);

  int get _percent => (_fraction * 100).round();

  Color get _color {
    if (_fraction >= 0.85) return AleraTokens.error;
    if (_fraction >= 0.6) return AleraTokens.warning;
    return AleraTokens.success;
  }

  String _formatTokens(int t) => formatTokenCount(t);

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final label = '$_percent% ctx';
    final tooltip =
        '${_formatTokens(usedTokens)} / ${_formatTokens(windowTokens)} tokens used';
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 28,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              child: LinearProgressIndicator(
                value: _fraction,
                backgroundColor: AleraTokens.border,
                color: color,
                minHeight: 4,
              ),
            ),
          ),
          const SizedBox(width: AleraTokens.space4),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
