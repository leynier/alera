part of 'settings_dialog.dart';

class _GeneralSettingsPane extends ConsumerWidget {
  const _GeneralSettingsPane({required this.general, required this.agents});

  final GeneralSettings general;
  final AgentSettings agents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starState = ref.watch(gitHubStarControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        AleraPanel(
          children: <Widget>[
            _WorkspaceDirectoryRow(
              value: general.workspaceDirectory,
              onChanged: (next) => ref
                  .read(settingsControllerProvider.notifier)
                  .updateWorkspaceDirectory(next),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        _SettingsGroup(
          title: 'Safety',
          description:
              'Confirmation prompts for destructive workspace actions.',
          children: <Widget>[
            _SwitchSettingRow(
              title: 'Confirm Project Removal',
              description:
                  'Ask before unregistering a project and deleting its workspace metadata.',
              value: general.confirmProjectRemoval,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setConfirmProjectRemoval(value),
            ),
            _SwitchSettingRow(
              title: 'Confirm Workspace Removal',
              description:
                  'Ask before removing a linked workspace and deleting its branch.',
              value: general.confirmWorkspaceRemoval,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setConfirmWorkspaceRemoval(value),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        _SettingsGroup(
          title: 'Agent status',
          description: 'Managed hooks let terminal tabs show agent state.',
          children: <Widget>[
            const AleraSettingRow(
              title: 'Alera CLI Skill',
              description:
                  'Install The Codex Skill That Teaches Agents To Use The Alera CLI.',
              controlWidth: 280,
              child: _AleraCliSkillControl(),
            ),
            _SwitchSettingRow(
              title: 'Codex Hooks',
              description:
                  'Use an Alera-managed Codex runtime home with status hooks.',
              value: agents.agentStatusHooks.codex,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.codex, value),
            ),
            _SwitchSettingRow(
              title: 'Claude Code Hooks',
              description:
                  'Use an Alera-managed Claude Code config with status hooks.',
              value: agents.agentStatusHooks.claude,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.claude, value),
            ),
            _SwitchSettingRow(
              title: 'GitHub Copilot Hooks',
              description: 'Use an Alera-managed GitHub Copilot home overlay.',
              value: agents.agentStatusHooks.copilot,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.copilot, value),
            ),
            _SwitchSettingRow(
              title: 'Cursor Hooks',
              description: 'Use an Alera-managed Cursor Agent plugin wrapper.',
              value: agents.agentStatusHooks.cursor,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.cursor, value),
            ),
            _SwitchSettingRow(
              title: 'Antigravity Hooks',
              description:
                  'Install Alera-managed Antigravity hooks for the agy CLI. Disable to remove only Alera-managed hook entries.',
              value: agents.agentStatusHooks.agy,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.agy, value),
            ),
            _SwitchSettingRow(
              title: 'OpenCode Hooks',
              description:
                  'Use an Alera-managed OpenCode config overlay with status plugin.',
              value: agents.agentStatusHooks.opencode,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.opencode, value),
            ),
            _SwitchSettingRow(
              title: 'Pi Hooks',
              description:
                  'Use an Alera-managed Pi agent overlay with status extension.',
              value: agents.agentStatusHooks.pi,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.pi, value),
            ),
            _SwitchSettingRow(
              title: 'Amp Hooks',
              description: 'Use an Alera-managed Amp config overlay.',
              value: agents.agentStatusHooks.amp,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusHookEnabled(AgentType.amp, value),
            ),
            _SwitchSettingRow(
              title: 'Agent Status Notifications',
              description:
                  'Show native notifications when an agent needs attention or finishes.',
              value: agents.agentStatusNotificationsEnabled,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setAgentStatusNotificationsEnabled(value),
            ),
            _SwitchSettingRow(
              title: 'Keep Computer Awake While Agents Are Working',
              description: _agentAwakeSettingDescription(
                Theme.of(context).platform,
              ),
              value: agents.keepComputerAwakeWhileAgentsWork,
              onChanged: (value) => ref
                  .read(settingsControllerProvider.notifier)
                  .setKeepComputerAwakeWhileAgentsWork(value),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space24),
        const UpdateSettingsSection(),
        if (starState != GitHubStarState.hidden) ...<Widget>[
          const SizedBox(height: AleraTokens.space24),
          _SupportAleraSection(state: starState),
        ],
      ],
    );
  }
}

class _AleraCliSkillControl extends ConsumerStatefulWidget {
  const _AleraCliSkillControl();

  @override
  ConsumerState<_AleraCliSkillControl> createState() =>
      _AleraCliSkillControlState();
}

class _AleraCliSkillControlState extends ConsumerState<_AleraCliSkillControl> {
  bool _installing = false;
  String? _status;

  Future<void> _install() async {
    if (_installing) {
      return;
    }
    setState(() {
      _installing = true;
      _status = null;
    });
    try {
      final result = await ref
          .read(aleraCliSkillServiceProvider)
          .installOrUpdate();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = result.summary;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = 'Install Failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
        });
      }
    }
  }

  Future<void> _copyCommand() async {
    await Clipboard.setData(
      const ClipboardData(text: aleraCliSkillInstallCommand),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _status = 'Install Command Copied';
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: <Widget>[
            SizedBox(
              height: _kSupportControlHeight,
              child: OutlinedButton.icon(
                onPressed: _installing ? null : _copyCommand,
                icon: const Icon(AleraIcons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ),
            SizedBox(
              height: _kSupportControlHeight,
              child: FilledButton.tonalIcon(
                onPressed: _installing ? null : _install,
                icon: _installing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AleraTokens.foreground,
                        ),
                      )
                    : const Icon(AleraIcons.download, size: 16),
                label: Text(_installing ? 'Installing' : 'Install / Update'),
              ),
            ),
          ],
        ),
        if (status != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          Text(
            status,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: status.startsWith('Install Failed')
                  ? AleraTokens.error
                  : AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ],
    );
  }
}

String _agentAwakeSettingDescription(TargetPlatform platform) {
  if (platform == TargetPlatform.windows) {
    return 'Keeps this computer and display awake while agents are working. Lid-close behavior follows this device\'s power settings.';
  }
  return 'Keeps this computer and display awake while agents are working. Alera also asks this device to stay awake when the lid is closed, subject to its power policy.';
}

class _SupportAleraSection extends ConsumerWidget {
  const _SupportAleraSection({required this.state});

  final GitHubStarState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(
            left: AleraTokens.space4,
            bottom: AleraTokens.space8,
          ),
          child: Text(
            'Support Alera',
            style: theme.textTheme.titleSmall?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        AleraPanel(
          children: <Widget>[
            AleraSettingRow(
              title: 'Star Alera on GitHub',
              description: null,
              child: _StarControl(
                state: state,
                onStar: () =>
                    ref.read(gitHubStarControllerProvider.notifier).star(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StarControl extends StatelessWidget {
  const _StarControl({required this.state, required this.onStar});

  final GitHubStarState state;
  final VoidCallback onStar;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedSwitcher(
        duration: AleraTokens.durationMid,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: _buildChild(),
      ),
    );
  }

  Widget _buildChild() {
    return switch (state) {
      GitHubStarState.loading => const _StarSkeleton(
        key: ValueKey<String>('loading'),
      ),
      GitHubStarState.notStarred => _StarButton(
        key: const ValueKey<String>('not-starred'),
        label: 'Star',
        onPressed: onStar,
      ),
      GitHubStarState.starring => const _StarButton(
        key: ValueKey<String>('starring'),
        label: 'Starring…',
        busy: true,
      ),
      GitHubStarState.starred => const _StarThanks(
        key: ValueKey<String>('starred'),
      ),
      GitHubStarState.error => _StarButton(
        key: const ValueKey<String>('error'),
        label: 'Try again',
        onPressed: onStar,
      ),
      GitHubStarState.hidden => const SizedBox.shrink(
        key: ValueKey<String>('hidden'),
      ),
    };
  }
}

@visibleForTesting
Widget buildStarControlForTesting({
  required GitHubStarState state,
  required VoidCallback onStar,
}) {
  return _StarControl(state: state, onStar: onStar);
}

class _StarButton extends StatelessWidget {
  const _StarButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kSupportControlHeight,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AleraTokens.foreground,
                ),
              )
            : const Icon(AleraIcons.star, size: 16),
        label: Text(label),
      ),
    );
  }
}

class _StarThanks extends StatelessWidget {
  const _StarThanks({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Thanks for starring Alera',
      liveRegion: true,
      child: SizedBox(
        height: _kSupportControlHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(AleraIcons.star, size: 16, color: AleraTokens.warning),
            const SizedBox(width: AleraTokens.space6),
            Text(
              'Thanks for the support!',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarSkeleton extends StatelessWidget {
  const _StarSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _kSupportControlHeight,
      width: 110,
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      ),
    );
  }
}

class _WorkspaceDirectoryRow extends StatefulWidget {
  const _WorkspaceDirectoryRow({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  State<_WorkspaceDirectoryRow> createState() => _WorkspaceDirectoryRowState();
}

class _WorkspaceDirectoryRowState extends State<_WorkspaceDirectoryRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(_WorkspaceDirectoryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        (widget.value ?? '') != _controller.text) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final next = _controller.text.trim();
    if (next.isEmpty) {
      if (widget.value != null) {
        widget.onChanged(null);
      }
      return;
    }
    if (next != widget.value) {
      widget.onChanged(next);
    }
  }

  Future<void> _browse() async {
    final picked = await getDirectoryPath(
      initialDirectory: _controller.text.isNotEmpty
          ? _controller.text
          : widget.value,
      confirmButtonText: 'Use as workspace directory',
      canCreateDirectories: true,
    );
    if (picked == null) {
      return;
    }
    _controller.text = picked;
    widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Workspace Directory',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            'Where new linked workspaces are created on disk. Existing '
            'workspaces are not moved. Leave empty to use the default '
            '(~/.alera/workspaces).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: AleraTextField(
                  controller: _controller,
                  onSubmitted: (_) => _commit(),
                  onEditingComplete: _commit,
                  hintText: '~/.alera/workspaces',
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              OutlinedButton.icon(
                onPressed: _browse,
                icon: const Icon(AleraIcons.folderOpen, size: 16),
                label: const Text('Browse'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
