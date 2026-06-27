part of 'settings_dialog.dart';

class _ProjectSettingsPane extends ConsumerStatefulWidget {
  const _ProjectSettingsPane();

  @override
  ConsumerState<_ProjectSettingsPane> createState() =>
      _ProjectSettingsPaneState();
}

class _ProjectSettingsPaneState extends ConsumerState<_ProjectSettingsPane> {
  String? _selectedProjectId;
  String? _editingProjectId;
  String? _seedSignature;
  List<_EditableCopyRule> _copyRules = const <_EditableCopyRule>[];
  List<String> _setupCommands = const <String>[];
  final Map<String, Future<ProjectConfig?>> _repoConfigFutures =
      <String, Future<ProjectConfig?>>{};
  String? _saveError;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectListProvider);
    final overridesAsync = ref.watch(projectConfigOverridesProvider);

    return projectsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ProjectSettingsError(message: error.toString()),
      data: (projects) {
        if (projects.isEmpty) {
          return const AleraEmptyState(
            icon: AleraIcons.folderOff,
            title: 'No Projects',
            message: 'Add A Project Before Configuring Workspace Setup.',
          );
        }
        final selected = _selectedProject(projects);
        return overridesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ProjectSettingsError(message: error.toString()),
          data: (overrides) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 220,
                  child: _ProjectConfigProjectList(
                    projects: projects,
                    selectedProjectId: selected.id,
                    overrideProjectIds: overrides.keys.toSet(),
                    onSelect: (project) {
                      setState(() {
                        _selectedProjectId = project.id;
                        _saveError = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: AleraTokens.space16),
                Expanded(
                  child: _ProjectConfigEditorLoader(
                    project: selected,
                    overrideConfig: overrides[selected.id],
                    repoConfigFuture: _repoConfigFuture(selected),
                    saveError: _saveError,
                    saving: _saving,
                    seedEditor: _seedEditor,
                    updateCopyRule: _updateCopyRule,
                    removeCopyRule: _removeCopyRule,
                    addCopyRule: _addCopyRule,
                    updateSetupCommand: _updateSetupCommand,
                    removeSetupCommand: _removeSetupCommand,
                    addSetupCommand: _addSetupCommand,
                    saveOverride: _saveOverride,
                    useRepoFile: overrides.containsKey(selected.id)
                        ? () => _useRepoFile(selected)
                        : null,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Project _selectedProject(List<Project> projects) {
    final selectedId = _selectedProjectId;
    if (selectedId != null) {
      for (final project in projects) {
        if (project.id == selectedId) {
          return project;
        }
      }
    }
    return projects.first;
  }

  Future<ProjectConfig?> _repoConfigFuture(Project project) {
    return _repoConfigFutures.putIfAbsent(project.id, () {
      return ref.read(projectConfigServiceProvider).loadRepoFile(project);
    });
  }

  ({List<_EditableCopyRule> copyRules, List<String> setupCommands})
  _seedEditor({required Project project, required ProjectConfig config}) {
    final signature = _projectConfigSignature(config);
    if (_editingProjectId == project.id && _seedSignature == signature) {
      return (copyRules: _copyRules, setupCommands: _setupCommands);
    }
    _editingProjectId = project.id;
    _seedSignature = signature;
    _copyRules = <_EditableCopyRule>[
      for (final rule in config.worktree.copy)
        _EditableCopyRule(
          from: rule.from,
          to: rule.to ?? '',
          overwrite: rule.overwrite,
        ),
    ];
    _setupCommands = <String>[...config.worktree.setup];
    _saveError = null;
    return (copyRules: _copyRules, setupCommands: _setupCommands);
  }

  void _updateCopyRule(int index, _EditableCopyRule rule) {
    setState(() {
      _copyRules = <_EditableCopyRule>[
        for (var i = 0; i < _copyRules.length; i += 1)
          if (i == index) rule else _copyRules[i],
      ];
    });
  }

  void _removeCopyRule(int index) {
    setState(() {
      _copyRules = <_EditableCopyRule>[
        for (var i = 0; i < _copyRules.length; i += 1)
          if (i != index) _copyRules[i],
      ];
    });
  }

  void _addCopyRule() {
    setState(() {
      _copyRules = <_EditableCopyRule>[
        ..._copyRules,
        const _EditableCopyRule(),
      ];
    });
  }

  void _updateSetupCommand(int index, String command) {
    setState(() {
      _setupCommands = <String>[
        for (var i = 0; i < _setupCommands.length; i += 1)
          if (i == index) command else _setupCommands[i],
      ];
    });
  }

  void _removeSetupCommand(int index) {
    setState(() {
      _setupCommands = <String>[
        for (var i = 0; i < _setupCommands.length; i += 1)
          if (i != index) _setupCommands[i],
      ];
    });
  }

  void _addSetupCommand() {
    setState(() {
      _setupCommands = <String>[..._setupCommands, ''];
    });
  }

  Future<void> _saveOverride(Project project) async {
    final config = _buildConfig();
    if (config == null) {
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ref
          .read(projectConfigServiceProvider)
          .saveUiOverride(projectId: project.id, config: config);
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _seedSignature = _projectConfigSignature(config);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _saveError = error.toString();
      });
    }
  }

  Future<void> _useRepoFile(Project project) async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ref.read(projectConfigServiceProvider).removeUiOverride(project.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _editingProjectId = null;
        _seedSignature = null;
        _copyRules = const <_EditableCopyRule>[];
        _setupCommands = const <String>[];
        _repoConfigFutures.remove(project.id);
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _saveError = error.toString();
      });
    }
  }

  ProjectConfig? _buildConfig() {
    final copyRules = <WorktreeCopyRule>[];
    for (var i = 0; i < _copyRules.length; i += 1) {
      final rule = _copyRules[i];
      final from = rule.from.trim();
      final to = rule.to.trim();
      if (from.isEmpty && to.isEmpty) {
        continue;
      }
      if (from.isEmpty) {
        setState(() => _saveError = 'Copy Source Is Required');
        return null;
      }
      try {
        copyRules.add(
          WorktreeCopyRule(
            from: normalizeProjectConfigPath(from, 'Copy Source'),
            to: to.isEmpty
                ? null
                : normalizeProjectConfigPath(to, 'Copy Destination'),
            overwrite: rule.overwrite,
          ),
        );
      } on ProjectConfigPathException catch (error) {
        setState(() => _saveError = error.message);
        return null;
      }
    }

    return ProjectConfig(
      worktree: WorktreeSetupConfig(
        copy: copyRules,
        setup: <String>[
          for (final command in _setupCommands)
            if (command.trim().isNotEmpty) command.trim(),
        ],
      ),
    );
  }
}

class _ProjectConfigEditorLoader extends ConsumerWidget {
  const _ProjectConfigEditorLoader({
    required this.project,
    required this.overrideConfig,
    required this.repoConfigFuture,
    required this.saveError,
    required this.saving,
    required this.seedEditor,
    required this.updateCopyRule,
    required this.removeCopyRule,
    required this.addCopyRule,
    required this.updateSetupCommand,
    required this.removeSetupCommand,
    required this.addSetupCommand,
    required this.saveOverride,
    required this.useRepoFile,
  });

  final Project project;
  final ProjectConfig? overrideConfig;
  final Future<ProjectConfig?> repoConfigFuture;
  final String? saveError;
  final bool saving;
  final ({List<_EditableCopyRule> copyRules, List<String> setupCommands})
  Function({required Project project, required ProjectConfig config})
  seedEditor;
  final void Function(int index, _EditableCopyRule rule) updateCopyRule;
  final ValueChanged<int> removeCopyRule;
  final VoidCallback addCopyRule;
  final void Function(int index, String command) updateSetupCommand;
  final ValueChanged<int> removeSetupCommand;
  final VoidCallback addSetupCommand;
  final Future<void> Function(Project project) saveOverride;
  final Future<void> Function()? useRepoFile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final override = overrideConfig;
    if (override != null) {
      final editorState = seedEditor(project: project, config: override);
      return _ProjectConfigEditor(
        project: project,
        sourceLabel: 'UI Override',
        copyRules: editorState.copyRules,
        setupCommands: editorState.setupCommands,
        saveError: saveError,
        saving: saving,
        updateCopyRule: updateCopyRule,
        removeCopyRule: removeCopyRule,
        addCopyRule: addCopyRule,
        updateSetupCommand: updateSetupCommand,
        removeSetupCommand: removeSetupCommand,
        addSetupCommand: addSetupCommand,
        saveOverride: saveOverride,
        useRepoFile: useRepoFile,
      );
    }

    return FutureBuilder<ProjectConfig?>(
      key: ValueKey<String>('repo-config-${project.id}'),
      future: repoConfigFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final editorState = seedEditor(
            project: project,
            config: ProjectConfig.empty,
          );
          return _ProjectConfigEditor(
            project: project,
            sourceLabel: 'Repo File Error',
            sourceError: snapshot.error.toString(),
            copyRules: editorState.copyRules,
            setupCommands: editorState.setupCommands,
            saveError: saveError,
            saving: saving,
            updateCopyRule: updateCopyRule,
            removeCopyRule: removeCopyRule,
            addCopyRule: addCopyRule,
            updateSetupCommand: updateSetupCommand,
            removeSetupCommand: removeSetupCommand,
            addSetupCommand: addSetupCommand,
            saveOverride: saveOverride,
            useRepoFile: null,
          );
        }
        final repoConfig = snapshot.data;
        final seed = repoConfig ?? ProjectConfig.empty;
        final editorState = seedEditor(project: project, config: seed);
        return _ProjectConfigEditor(
          project: project,
          sourceLabel: repoConfig == null ? 'None' : 'Repo File',
          copyRules: editorState.copyRules,
          setupCommands: editorState.setupCommands,
          saveError: saveError,
          saving: saving,
          updateCopyRule: updateCopyRule,
          removeCopyRule: removeCopyRule,
          addCopyRule: addCopyRule,
          updateSetupCommand: updateSetupCommand,
          removeSetupCommand: removeSetupCommand,
          addSetupCommand: addSetupCommand,
          saveOverride: saveOverride,
          useRepoFile: null,
        );
      },
    );
  }
}

class _ProjectConfigProjectList extends StatelessWidget {
  const _ProjectConfigProjectList({
    required this.projects,
    required this.selectedProjectId,
    required this.overrideProjectIds,
    required this.onSelect,
  });

  final List<Project> projects;
  final String selectedProjectId;
  final Set<String> overrideProjectIds;
  final ValueChanged<Project> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraPanel(
      children: <Widget>[
        for (final project in projects)
          InkWell(
            onTap: () => onSelect(project),
            child: Container(
              padding: const EdgeInsets.all(AleraTokens.space12),
              color: project.id == selectedProjectId
                  ? AleraTokens.accentSubtle
                  : Colors.transparent,
              child: Row(
                children: <Widget>[
                  Icon(
                    AleraIcons.folderSpecial,
                    size: 16,
                    color: project.id == selectedProjectId
                        ? AleraTokens.accent
                        : AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          project.name,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AleraTokens.foreground,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: AleraTokens.space2),
                        Text(
                          overrideProjectIds.contains(project.id)
                              ? 'UI Override'
                              : 'Repo File',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ProjectConfigEditor extends StatelessWidget {
  const _ProjectConfigEditor({
    required this.project,
    required this.sourceLabel,
    required this.copyRules,
    required this.setupCommands,
    required this.saveError,
    required this.saving,
    required this.updateCopyRule,
    required this.removeCopyRule,
    required this.addCopyRule,
    required this.updateSetupCommand,
    required this.removeSetupCommand,
    required this.addSetupCommand,
    required this.saveOverride,
    required this.useRepoFile,
    this.sourceError,
  });

  final Project project;
  final String sourceLabel;
  final String? sourceError;
  final List<_EditableCopyRule> copyRules;
  final List<String> setupCommands;
  final String? saveError;
  final bool saving;
  final void Function(int index, _EditableCopyRule rule) updateCopyRule;
  final ValueChanged<int> removeCopyRule;
  final VoidCallback addCopyRule;
  final void Function(int index, String command) updateSetupCommand;
  final ValueChanged<int> removeSetupCommand;
  final VoidCallback addSetupCommand;
  final Future<void> Function(Project project) saveOverride;
  final Future<void> Function()? useRepoFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SettingsGroup(
          title: project.name,
          description: 'UI Overrides Take Precedence Over Repo Files.',
          children: <Widget>[
            AleraSettingRow(
              title: 'Config Source',
              description: project.repoPath,
              controlWidth: 150,
              child: Align(
                alignment: Alignment.centerRight,
                child: _ProjectConfigSourceBadge(label: sourceLabel),
              ),
            ),
            if (sourceError != null)
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space16),
                child: Text(
                  sourceError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.error,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        _SettingsGroup(
          title: 'Copy Rules',
          description: 'Files And Directories Copied From The Main Worktree.',
          children: <Widget>[
            if (copyRules.isEmpty)
              const _ProjectConfigEmptyRow(message: 'No Copy Rules')
            else
              for (var i = 0; i < copyRules.length; i += 1)
                _CopyRuleEditorRow(
                  key: ValueKey<String>('copy-rule-$i'),
                  rule: copyRules[i],
                  onChanged: (rule) => updateCopyRule(i, rule),
                  onRemove: () => removeCopyRule(i),
                ),
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: addCopyRule,
                  icon: const Icon(AleraIcons.add, size: 16),
                  label: const Text('Add Copy Rule'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space16),
        _SettingsGroup(
          title: 'Setup Commands',
          description: 'Commands Run From The New Linked Workspace.',
          children: <Widget>[
            if (setupCommands.isEmpty)
              const _ProjectConfigEmptyRow(message: 'No Setup Commands')
            else
              for (var i = 0; i < setupCommands.length; i += 1)
                _SetupCommandEditorRow(
                  key: ValueKey<String>('setup-command-$i'),
                  command: setupCommands[i],
                  onChanged: (command) => updateSetupCommand(i, command),
                  onRemove: () => removeSetupCommand(i),
                ),
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: addSetupCommand,
                  icon: const Icon(AleraIcons.add, size: 16),
                  label: const Text('Add Setup Command'),
                ),
              ),
            ),
          ],
        ),
        if (saveError != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          Text(
            saveError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.error,
            ),
          ),
        ],
        const SizedBox(height: AleraTokens.space16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AleraTokens.space8,
          runSpacing: AleraTokens.space8,
          children: <Widget>[
            if (useRepoFile != null) ...<Widget>[
              OutlinedButton(
                onPressed: saving ? null : useRepoFile,
                child: const Text('Use Repo File'),
              ),
            ],
            FilledButton.icon(
              onPressed: saving ? null : () => saveOverride(project),
              icon: saving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AleraIcons.save, size: 16),
              label: Text(saving ? 'Saving' : 'Save Override'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CopyRuleEditorRow extends StatelessWidget {
  const _CopyRuleEditorRow({
    super.key,
    required this.rule,
    required this.onChanged,
    required this.onRemove,
  });

  final _EditableCopyRule rule;
  final ValueChanged<_EditableCopyRule> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: _ProjectConfigTextField(
              key: const ValueKey<String>('copy-rule-from-field'),
              value: rule.from,
              labelText: 'From',
              hintText: '.env',
              onChanged: (value) => onChanged(rule.copyWith(from: value)),
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: _ProjectConfigTextField(
              key: const ValueKey<String>('copy-rule-to-field'),
              value: rule.to,
              labelText: 'To',
              hintText: 'Defaults To From',
              onChanged: (value) => onChanged(rule.copyWith(to: value)),
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Tooltip(
            message: 'Overwrite Existing Destination',
            child: Checkbox(
              value: rule.overwrite,
              onChanged: (value) =>
                  onChanged(rule.copyWith(overwrite: value ?? false)),
            ),
          ),
          AleraIconButton(
            tooltip: 'Remove Copy Rule',
            onPressed: onRemove,
            icon: AleraIcons.delete,
          ),
        ],
      ),
    );
  }
}

class _SetupCommandEditorRow extends StatelessWidget {
  const _SetupCommandEditorRow({
    super.key,
    required this.command,
    required this.onChanged,
    required this.onRemove,
  });

  final String command;
  final ValueChanged<String> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ProjectConfigTextField(
              key: const ValueKey<String>('setup-command-field'),
              value: command,
              labelText: 'Command',
              hintText: 'make bootstrap',
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          AleraIconButton(
            tooltip: 'Remove Setup Command',
            onPressed: onRemove,
            icon: AleraIcons.delete,
          ),
        ],
      ),
    );
  }
}

class _ProjectConfigTextField extends StatefulWidget {
  const _ProjectConfigTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.labelText,
    this.hintText,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? labelText;
  final String? hintText;

  @override
  State<_ProjectConfigTextField> createState() =>
      _ProjectConfigTextFieldState();
}

class _ProjectConfigTextFieldState extends State<_ProjectConfigTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_ProjectConfigTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AleraTextField(
      controller: _controller,
      labelText: widget.labelText,
      hintText: widget.hintText,
      onChanged: widget.onChanged,
    );
  }
}

class _ProjectConfigSourceBadge extends StatelessWidget {
  const _ProjectConfigSourceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space4,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.accentSubtle,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: AleraTokens.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProjectConfigEmptyRow extends StatelessWidget {
  const _ProjectConfigEmptyRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundMuted,
        ),
      ),
    );
  }
}

class _ProjectSettingsError extends StatelessWidget {
  const _ProjectSettingsError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      message,
      style: theme.textTheme.bodySmall?.copyWith(color: AleraTokens.error),
    );
  }
}

class _EditableCopyRule {
  const _EditableCopyRule({
    this.from = '',
    this.to = '',
    this.overwrite = false,
  });

  final String from;
  final String to;
  final bool overwrite;

  _EditableCopyRule copyWith({String? from, String? to, bool? overwrite}) {
    return _EditableCopyRule(
      from: from ?? this.from,
      to: to ?? this.to,
      overwrite: overwrite ?? this.overwrite,
    );
  }
}

String _projectConfigSignature(ProjectConfig config) {
  final buffer = StringBuffer();
  for (final rule in config.worktree.copy) {
    buffer
      ..write(rule.from)
      ..write('\u{1f}')
      ..write(rule.to ?? '')
      ..write('\u{1f}')
      ..write(rule.overwrite)
      ..write('\u{1e}');
  }
  buffer.write('\u{1d}');
  for (final command in config.worktree.setup) {
    buffer
      ..write(command)
      ..write('\u{1e}');
  }
  return buffer.toString();
}
