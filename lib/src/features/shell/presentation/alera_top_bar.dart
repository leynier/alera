import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

class AleraTopBar extends StatelessWidget {
  const AleraTopBar({
    super.key,
    required this.workspaceName,
    required this.sessionTitle,
    required this.isBusy,
    this.onOpenAcpPlayground,
  });

  final String? workspaceName;
  final String? sessionTitle;
  final bool isBusy;
  final VoidCallback? onOpenAcpPlayground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: AleraTokens.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.bolt, size: 18, color: AleraTokens.accent),
          const SizedBox(width: AleraTokens.space8),
          Expanded(child: _buildBreadcrumb(theme)),
          AnimatedOpacity(
            opacity: isBusy ? 1.0 : 0.0,
            duration: AleraTokens.durationMid,
            child: const RepaintBoundary(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: AleraTokens.accent,
                ),
              ),
            ),
          ),
          if (onOpenAcpPlayground != null) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            IconButton(
              onPressed: onOpenAcpPlayground,
              tooltip: 'ACP playground (experimental)',
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: const Icon(
                Icons.science_outlined,
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ],
          const SizedBox(width: AleraTokens.space8),
        ],
      ),
    );
  }

  Widget _buildBreadcrumb(ThemeData theme) {
    final workspace = workspaceName;
    if (workspace == null || workspace.isEmpty) {
      return Text(
        'Alera',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      );
    }
    final session = sessionTitle;
    if (session == null || session.isEmpty) {
      return Text(
        workspace,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            workspace,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AleraTokens.space4),
          child: Icon(
            Icons.chevron_right,
            size: 14,
            color: AleraTokens.foregroundFaint,
          ),
        ),
        Flexible(
          child: Text(
            session,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
