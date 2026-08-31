import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:flutter/material.dart';

class const SidebarCollapsedRail({
  super.key,
  required final List<Project> projects,
  required final String? activeProjectId,
  required final Map<String, int> workspaceCountByProject,
  required final ValueChanged<Project> onSelectProject,
  required final VoidCallback onAddProject,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
      child: Column(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
              itemCount: projects.length,
              itemBuilder: (_, index) {
                final project = projects[index];
                final isActive = project.id == activeProjectId;
                final count = workspaceCountByProject[project.id] ?? 0;
                return _RailProjectAvatar(
                  project: project,
                  active: isActive,
                  workspaceCount: count,
                  onTap: () => onSelectProject(project),
                );
              },
            ),
          ),
          Center(
            child: AleraIconButton(
              tooltip: 'Add Project',
              icon: AleraIcons.newFolder,
              iconSize: 14,
              borderColor: AleraTokens.borderSubtle,
              onPressed: onAddProject,
            ),
          ),
        ],
      ),
    );
  }
}

class const _RailProjectAvatar({
  required final Project project,
  required final bool active,
  required final int workspaceCount,
  required final VoidCallback onTap,
}) extends StatefulWidget {
  @override
  State<_RailProjectAvatar> createState() => _RailProjectAvatarState();
}

class _RailProjectAvatarState extends State<_RailProjectAvatar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = widget.project.name.isEmpty
        ? '?'
        : widget.project.name.characters.first.toUpperCase();
    final emphasized = widget.active || _hovered;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Center(
        child: Tooltip(
          message: widget.project.name,
          waitDuration: const Duration(milliseconds: 300),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: InkWell(
              borderRadius: .circular(AleraTokens.radiusMd),
              mouseCursor: SystemMouseCursors.click,
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: AleraTokens.durationFast,
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.active
                      ? AleraTokens.surfaceElevated
                      : (_hovered ? AleraTokens.surface : Colors.transparent),
                  borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                  border: Border.all(
                    color: widget.active
                        ? AleraTokens.border
                        : AleraTokens.borderSubtle,
                  ),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: emphasized
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                      fontWeight: .w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
