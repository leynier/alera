import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:flutter/material.dart';

class ProjectTile extends StatefulWidget {
  const ProjectTile({
    super.key,
    required this.project,
    required this.expanded,
    required this.chatCount,
    required this.onToggle,
    required this.onNewChat,
    required this.onRemoveProject,
  });

  final Project project;
  final bool expanded;
  final int chatCount;
  final VoidCallback onToggle;
  final VoidCallback onNewChat;
  final VoidCallback onRemoveProject;

  @override
  State<ProjectTile> createState() => _ProjectTileState();
}

class _ProjectTileState extends State<ProjectTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onToggle,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        child: AnimatedContainer(
          duration: AleraTokens.durationFast,
          decoration: BoxDecoration(
            color: _hovered ? AleraTokens.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space6,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                widget.expanded ? Icons.expand_more : Icons.chevron_right,
                size: 14,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space4),
              Expanded(
                child: Text(
                  widget.project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: _hovered
                        ? AleraTokens.foreground
                        : AleraTokens.foregroundMuted,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!widget.expanded && widget.chatCount > 0 && !_hovered)
                Padding(
                  padding: const EdgeInsets.only(left: AleraTokens.space4),
                  child: Text(
                    widget.chatCount.toString(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundFaint,
                    ),
                  ),
                ),
              AnimatedOpacity(
                opacity: _hovered ? 1 : 0,
                duration: AleraTokens.durationFast,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'New chat in this project',
                      onPressed: widget.onNewChat,
                      icon: const Icon(Icons.add, size: 14),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Project options',
                      icon: const Icon(Icons.more_horiz, size: 14),
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      onSelected: (value) {
                        if (value == 'remove') {
                          widget.onRemoveProject();
                        }
                      },
                      itemBuilder: (_) => const <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'remove',
                          child: Text('Remove project'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
