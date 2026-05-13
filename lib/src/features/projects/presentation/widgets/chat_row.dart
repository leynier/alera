import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/chat_summary.dart';
import 'package:alera/src/features/projects/domain/worktree.dart';
import 'package:flutter/material.dart';

class ChatRow extends StatefulWidget {
  const ChatRow({
    super.key,
    required this.chat,
    required this.worktree,
    required this.isActive,
    required this.isPinned,
    required this.onTap,
    required this.onDelete,
    required this.onTogglePin,
    this.leading,
    this.dense = false,
  });

  final ChatSummary chat;
  final Worktree? worktree;
  final bool isActive;
  final bool isPinned;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;
  final Widget? leading;
  final bool dense;

  @override
  State<ChatRow> createState() => _ChatRowState();
}

class _ChatRowState extends State<ChatRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;
    final titleStyle = theme.textTheme.bodySmall?.copyWith(
      color: isActive ? AleraTokens.foreground : AleraTokens.foregroundMuted,
      fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Stack(
          children: <Widget>[
            AnimatedContainer(
              duration: AleraTokens.durationMid,
              decoration: BoxDecoration(
                color: isActive
                    ? AleraTokens.surfaceElevated
                    : (_hovered ? AleraTokens.surface : Colors.transparent),
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              ),
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AleraTokens.space8,
                    vertical: widget.dense
                        ? AleraTokens.space4
                        : AleraTokens.space6,
                  ),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 16,
                        child: widget.leading ??
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 12,
                              color: isActive
                                  ? AleraTokens.foreground
                                  : AleraTokens.foregroundFaint,
                            ),
                      ),
                      const SizedBox(width: AleraTokens.space8),
                      Expanded(
                        child: Text(
                          widget.chat.title.isEmpty
                              ? 'Untitled chat'
                              : widget.chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                      if (widget.worktree case final Worktree worktree) ...<Widget>[
                        const SizedBox(width: AleraTokens.space6),
                        _BranchChip(name: worktree.name),
                      ],
                      // Reserve width for hover actions so the row width is
                      // stable; they fade in on hover/active.
                      AnimatedOpacity(
                        opacity: (_hovered || isActive) ? 1 : 0,
                        duration: AleraTokens.durationFast,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const SizedBox(width: AleraTokens.space4),
                            _HoverIconButton(
                              tooltip: widget.isPinned ? 'Unpin' : 'Pin chat',
                              icon: widget.isPinned
                                  ? Icons.push_pin
                                  : Icons.push_pin_outlined,
                              onPressed: widget.onTogglePin,
                              active: widget.isPinned,
                            ),
                            _HoverIconButton(
                              tooltip: 'Delete chat',
                              icon: Icons.close,
                              onPressed: widget.onDelete,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (isActive)
              Positioned(
                left: 0,
                top: 4,
                bottom: 4,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: AleraTokens.accent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BranchChip extends StatelessWidget {
  const _BranchChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 110),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space6,
          vertical: 1,
        ),
        decoration: BoxDecoration(
          color: AleraTokens.surface,
          borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          border: Border.all(color: AleraTokens.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.alt_route,
              size: 10,
              color: AleraTokens.foregroundFaint,
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoverIconButton extends StatelessWidget {
  const _HoverIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 12,
        color: active
            ? AleraTokens.foreground
            : AleraTokens.foregroundMuted,
      ),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
    );
  }
}
