import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/shared/presentation/dropdown_entry.dart';
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
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: AnimatedContainer(
          duration: AleraTokens.durationFast,
          decoration: BoxDecoration(
            color: _hovered ? AleraTokens.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space4,
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
                    _ProjectHoverIconButton(
                      tooltip: 'New chat in this project',
                      onPressed: widget.onNewChat,
                      icon: Icons.add,
                    ),
                    _ProjectOptionsButton(
                      onRemoveProject: widget.onRemoveProject,
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

class _ProjectHoverIconButton extends StatelessWidget {
  const _ProjectHoverIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(icon, size: 14, color: AleraTokens.foregroundMuted),
        ),
      ),
    );
  }
}

class _ProjectOptionsButton extends StatelessWidget {
  const _ProjectOptionsButton({required this.onRemoveProject});

  final VoidCallback onRemoveProject;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: 'Project options',
        child: InkWell(
          onTap: () async {
            final button = context.findRenderObject()! as RenderBox;
            final overlay =
                Navigator.of(context).overlay!.context.findRenderObject()!
                    as RenderBox;
            final topLeft = button.localToGlobal(
              Offset.zero,
              ancestor: overlay,
            );
            final bottomRight = button.localToGlobal(
              button.size.bottomRight(Offset.zero),
              ancestor: overlay,
            );
            final selected = await showMenu<String>(
              context: context,
              position: RelativeRect.fromRect(
                Rect.fromPoints(topLeft, bottomRight),
                Offset.zero & overlay.size,
              ),
              items: const <PopupMenuEntry<String>>[
                DropdownEntry<String>(value: 'remove', label: 'Remove project'),
              ],
            );
            if (selected == 'remove') {
              onRemoveProject();
            }
          },
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          child: const SizedBox(
            width: 24,
            height: 24,
            child: Icon(
              Icons.more_horiz,
              size: 14,
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ),
      ),
    );
  }
}
