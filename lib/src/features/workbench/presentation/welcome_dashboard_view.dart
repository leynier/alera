part of 'welcome_dashboard.dart';

class const _HomeComposerFrame({required final Widget child})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= AleraTokens.wideContentBreakpoint;
        final horizontal = wide ? AleraTokens.space32 : AleraTokens.space16;
        final vertical = AleraTokens.space32;
        final available = constraints.maxHeight.isFinite
            ? constraints.maxHeight - vertical * 2
            : 0.0;
        final contentWidth = constraints.maxWidth - horizontal * 2;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontal,
            vertical: vertical,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: available < 0 ? 0 : available,
              // The scroll view loosens the width, so without a minimum the
              // column shrinks to the composer and stays on the leading edge.
              minWidth: contentWidth < 0 ? 0 : contentWidth,
            ),
            child: Column(
              mainAxisAlignment: .center,
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AleraTokens.conversationMaxWidth,
                  ),
                  child: child,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class const _HomeComposerQuestion() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'What should we build?',
      textAlign: .center,
      style: _homeHeadline(context),
    );
  }
}

class _HomeComposerHeading extends StatelessWidget {
  const _HomeComposerHeading({
    required this.projectName,
    required this.onPickProject,
  });

  final String projectName;
  final Future<void> Function(BuildContext context) onPickProject;

  @override
  Widget build(BuildContext context) {
    final headline = _homeHeadline(context);
    return Wrap(
      alignment: .center,
      crossAxisAlignment: .center,
      children: <Widget>[
        Text('What should we build in ', style: headline),
        TextButton(
          key: const ValueKey<String>('home-composer-project'),
          style: _homeInlineButtonStyle(AleraTokens.foreground),
          onPressed: () => onPickProject(context),
          child: Text(
            projectName,
            style: headline?.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: AleraTokens.foregroundMuted,
            ),
          ),
        ),
        Text('?', style: headline),
      ],
    );
  }
}

class _HomeComposerSetup extends StatelessWidget {
  const _HomeComposerSetup({
    required this.needsProject,
    required this.needsProfile,
    required this.loadingProfiles,
    required this.onAddProject,
    required this.onCreateProfile,
    this.profileError,
  });

  final bool needsProject;
  final bool needsProfile;
  final bool loadingProfiles;
  final VoidCallback onAddProject;
  final VoidCallback onCreateProfile;
  final String? profileError;

  @override
  Widget build(BuildContext context) {
    if (loadingProfiles) {
      return const Padding(
        padding: EdgeInsets.only(top: AleraTokens.space32),
        child: SizedBox.square(
          dimension: AleraTokens.iconLg,
          child: CircularProgressIndicator(strokeWidth: AleraTokens.strokeSm),
        ),
      );
    }
    final both = needsProject && needsProfile;
    return Column(
      mainAxisSize: .min,
      children: <Widget>[
        AleraEmptyState(
          icon: needsProject ? AleraIcons.newFolder : AleraIcons.agent,
          title: needsProject ? 'No projects yet' : 'No agent profiles',
          message: both
              ? 'Add a project and create an agent profile to start an agent from a prompt.'
              : needsProject
              ? 'Add a project to start an agent from a prompt.'
              : 'Create an agent profile to start an agent from a prompt.',
          action: Wrap(
            alignment: .center,
            spacing: AleraTokens.space8,
            runSpacing: AleraTokens.space8,
            children: <Widget>[
              if (needsProject)
                FilledButton(
                  key: const ValueKey<String>('home-composer-add-project'),
                  onPressed: onAddProject,
                  child: const Text('Add Project'),
                ),
              if (needsProfile)
                both
                    ? OutlinedButton(
                        key: const ValueKey<String>(
                          'home-composer-create-profile',
                        ),
                        onPressed: onCreateProfile,
                        child: const Text('Create Agent Profile'),
                      )
                    : FilledButton(
                        key: const ValueKey<String>(
                          'home-composer-create-profile',
                        ),
                        onPressed: onCreateProfile,
                        child: const Text('Create Agent Profile'),
                      ),
            ],
          ),
        ),
        if (profileError case final String error) ...<Widget>[
          Text(
            error,
            textAlign: .center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.error),
          ),
        ],
      ],
    );
  }
}

TextStyle? _homeHeadline(BuildContext context) {
  return Theme.of(context).textTheme.headlineSmall
      ?.copyWith(fontWeight: .w600, color: AleraTokens.foreground);
}

extension _WelcomeDashboardLabels on _WelcomeDashboardState {
  String _selectedParentLabel(List<Workspace> parents, WorkbenchState state) {
    final parentId = _selectedParentId;
    if (parentId == null) {
      return 'No Parent';
    }
    for (final workspace in parents) {
      if (workspace.id != parentId) {
        continue;
      }
      return _homeParentLabel(workspace, <String, String>{
        for (final project in state.projects) project.id: project.name,
      });
    }
    return 'No Parent';
  }
}

String _homeParentLabel(Workspace workspace, Map<String, String> projectNames) {
  final branch = workspace.branch?.trim();
  final suffix = branch == null || branch.isEmpty ? '' : ' - $branch';
  final projectName = projectNames[workspace.projectId] ?? workspace.projectId;
  return '$projectName / ${workspace.name}$suffix';
}

ButtonStyle _homeInlineButtonStyle(Color foreground) {
  return TextButton.styleFrom(
    foregroundColor: foreground,
    minimumSize: Size.zero,
    padding: EdgeInsets.zero,
    tapTargetSize: .shrinkWrap,
    visualDensity: .compact,
  );
}

class _HomeComposerChip extends StatelessWidget {
  const _HomeComposerChip({
    super.key,
    required this.label,
    this.leading,
    this.onPressed,
    this.ellipsize = false,
  });

  final String label;
  final Widget? leading;
  final void Function(BuildContext context)? onPressed;
  final bool ellipsize;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final pressed = onPressed;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: AleraTokens.foregroundMuted,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space4,
        ),
        tapTargetSize: .shrinkWrap,
        visualDensity: .compact,
      ),
      onPressed: pressed == null ? null : () => pressed(context),
      child: Row(
        mainAxisSize: .min,
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: AleraTokens.space4),
          ],
          ellipsize
              ? Flexible(
                  child: Text(
                    label,
                    style: style,
                    maxLines: 1,
                    overflow: .ellipsis,
                  ),
                )
              : Text(label, style: style),
          if (onPressed != null) ...<Widget>[
            const SizedBox(width: AleraTokens.space4),
            const Icon(
              AleraIcons.chevronDown,
              size: AleraTokens.iconSm,
              color: AleraTokens.foregroundMuted,
            ),
          ],
        ],
      ),
    );
  }
}
