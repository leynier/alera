import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_path_display.dart';
import 'package:flutter/material.dart';

/// A compact changed-file row: status letter, file name over its folder, line
/// counts, and, when the runtime allows it, a one-tap stage or unstage.
class const SourceControlChangeRow({
  super.key,
  required final MobileGitChange change,
  required final VoidCallback onTap,
  final VoidCallback? onLongPress,
  final bool showStageToggle = false,

  /// Null disables the toggle, for example while another write runs.
  final VoidCallback? onToggleStaged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = workspaceFileBaseName(change.path);
    final parent = workspaceFileParentLabel(change.path);
    final (letter, color) = _statusMark(change.status);
    final toggle = showStageToggle && (change.canStage || change.canUnstage);
    return Tooltip(
      message: change.path,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AleraTokens.minTapTarget,
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: AleraTokens.space16,
              right: toggle ? AleraTokens.space4 : AleraTokens.space16,
              top: AleraTokens.space8,
              bottom: AleraTokens.space8,
            ),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  child: Text(
                    letter,
                    textAlign: .center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: .w600,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: <Widget>[
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (parent != null)
                        Text(
                          parent,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                _LineStats(added: change.added, removed: change.removed),
                if (toggle)
                  AleraIconButton(
                    tooltip: change.canUnstage ? 'Unstage' : 'Stage',
                    icon: change.canUnstage
                        ? AleraIcons.gitUnstage
                        : AleraIcons.gitStage,
                    onPressed: onToggleStaged,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class const _LineStats({required final int? added, required final int? removed})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final visibleAdded = added != null && added! > 0 ? added : null;
    final visibleRemoved = removed != null && removed! > 0 ? removed : null;
    if (visibleAdded == null && visibleRemoved == null) {
      return const SizedBox.shrink();
    }
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        if (visibleAdded case final added?)
          Text('+$added', style: style?.copyWith(color: AleraTokens.success)),
        if (visibleRemoved case final removed?) ...<Widget>[
          if (visibleAdded != null) const SizedBox(width: AleraTokens.space6),
          Text('-$removed', style: style?.copyWith(color: AleraTokens.error)),
        ],
      ],
    );
  }
}

(String, Color) _statusMark(String status) {
  return switch (status) {
    'added' => ('A', AleraTokens.success),
    'untracked' => ('U', AleraTokens.success),
    'deleted' => ('D', AleraTokens.error),
    'renamed' => ('R', AleraTokens.warning),
    'copied' => ('C', AleraTokens.warning),
    'modified' => ('M', AleraTokens.warning),
    _ => (
      status.isEmpty ? 'M' : status[0].toUpperCase(),
      AleraTokens.foregroundMuted,
    ),
  };
}
