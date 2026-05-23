import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:flutter/material.dart';

class SidebarCollapsedRail extends StatelessWidget {
  const SidebarCollapsedRail({
    super.key,
    required this.projects,
    required this.activeProjectId,
    required this.chatCountByProject,
    required this.onSelectProject,
    required this.onAddProject,
  });

  final List<Project> projects;
  final String? activeProjectId;
  final Map<String, int> chatCountByProject;
  final ValueChanged<Project> onSelectProject;
  final VoidCallback onAddProject;

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
                final count = chatCountByProject[project.id] ?? 0;
                return _RailProjectAvatar(
                  project: project,
                  active: isActive,
                  chatCount: count,
                  onTap: () => onSelectProject(project),
                );
              },
            ),
          ),
          Tooltip(
            message: 'Add project',
            child: _RailIconButton(
              icon: Icons.create_new_folder_outlined,
              onPressed: onAddProject,
            ),
          ),
        ],
      ),
    );
  }
}

class _RailProjectAvatar extends StatefulWidget {
  const _RailProjectAvatar({
    required this.project,
    required this.active,
    required this.chatCount,
    required this.onTap,
  });

  final Project project;
  final bool active;
  final int chatCount;
  final VoidCallback onTap;

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
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
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
                      fontWeight: FontWeight.w600,
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

class _RailIconButton extends StatelessWidget {
  const _RailIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 14, color: AleraTokens.foregroundMuted),
        style: IconButton.styleFrom(
          minimumSize: const Size(30, 30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            side: const BorderSide(color: AleraTokens.borderSubtle),
          ),
        ),
      ),
    );
  }
}
