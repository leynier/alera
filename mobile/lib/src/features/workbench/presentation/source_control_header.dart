import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:flutter/material.dart';

/// Branch, sync position and change totals, with the Source Control menu when
/// the runtime accepts writes.
class const SourceControlHeader({
  super.key,
  required final MobileGitStatusSnapshot snapshot,
  final VoidCallback? onBranchTap,
  final VoidCallback? onMoreActions,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileCount = snapshot.changedFileCount;
    final repository = snapshot.repository;
    final syncLabel = <String>[
      if (repository.ahead > 0) '↑${repository.ahead}',
      if (repository.behind > 0) '↓${repository.behind}',
    ].join(' ');
    final branch = Row(
      children: <Widget>[
        const Icon(
          AleraIcons.gitBranch,
          size: 16,
          color: AleraTokens.foregroundMuted,
        ),
        const SizedBox(width: AleraTokens.space8),
        Flexible(
          child: Text(
            snapshot.branch == null || repository.detached
                ? 'Detached'
                : snapshot.branch!,
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.titleSmall,
          ),
        ),
        if (syncLabel.isNotEmpty) ...<Widget>[
          const SizedBox(width: AleraTokens.space8),
          Text(
            syncLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AleraTokens.space16,
        0,
        onMoreActions == null ? AleraTokens.space16 : AleraTokens.space4,
        AleraTokens.space8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: onBranchTap == null
                ? branch
                : InkWell(
                    onTap: onBranchTap,
                    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: AleraTokens.minTapTarget,
                      ),
                      child: branch,
                    ),
                  ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Text(
            '$fileCount ${fileCount == 1 ? 'file' : 'files'}',
            style: theme.textTheme.bodySmall,
          ),
          if (snapshot.addedLineCount > 0) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            Text(
              '+${snapshot.addedLineCount}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.success,
              ),
            ),
          ],
          if (snapshot.removedLineCount > 0) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            Text(
              '-${snapshot.removedLineCount}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.error,
              ),
            ),
          ],
          if (onMoreActions != null)
            AleraIconButton(
              tooltip: 'Source Control Actions',
              icon: AleraIcons.more,
              onPressed: onMoreActions,
            ),
        ],
      ),
    );
  }
}
