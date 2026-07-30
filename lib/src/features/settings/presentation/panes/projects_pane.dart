import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/features/projects/domain/project_config_paths.dart';
import 'package:alera/src/features/projects/domain/project_selection_order.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/features/settings/presentation/panes/project_config_editor.dart';
import 'package:alera/src/features/settings/presentation/panes/project_config_editor_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProjectSettingsPane extends ConsumerStatefulWidget {
  const ProjectSettingsPane({super.key});

  @override
  ConsumerState<ProjectSettingsPane> createState() =>
      _ProjectSettingsPaneState();
}

class _ProjectSettingsPaneState extends ConsumerState<ProjectSettingsPane> {
  String? _selectedProjectId;
  String? _editingProjectId;
  String? _seedSignature;
  List<EditableCopyRule> _copyRules = const <EditableCopyRule>[];
  List<String> _setupCommands = const <String>[];
  GitHostingProvider? _gitHostingProvider;
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
        final orderedProjects = sortProjectsForSelection(projects);
        final selected = _selectedProject(orderedProjects);
        return overridesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ProjectSettingsError(message: error.toString()),
          data: (overrides) {
            return AleraMasterDetail(
              masterTitle: 'Projects',
              master: SingleChildScrollView(
                child: _ProjectConfigProjectList(
                  projects: orderedProjects,
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
              detail: SingleChildScrollView(
                child: ProjectConfigEditorLoader(
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
                  onGitHostingProviderChanged: _setGitHostingProvider,
                ),
              ),
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

  ({
    List<EditableCopyRule> copyRules,
    List<String> setupCommands,
    GitHostingProvider? gitHostingProvider,
  })
  _seedEditor({required Project project, required ProjectConfig config}) {
    final signature = projectConfigSignature(config);
    if (_editingProjectId == project.id && _seedSignature == signature) {
      return (
        copyRules: _copyRules,
        setupCommands: _setupCommands,
        gitHostingProvider: _gitHostingProvider,
      );
    }
    _editingProjectId = project.id;
    _seedSignature = signature;
    _copyRules = <EditableCopyRule>[
      for (final rule in config.worktree.copy)
        EditableCopyRule(
          from: rule.from,
          to: rule.to ?? '',
          overwrite: rule.overwrite,
        ),
    ];
    _setupCommands = <String>[...config.worktree.setup];
    _gitHostingProvider = config.gitHostingProvider;
    _saveError = null;
    return (
      copyRules: _copyRules,
      setupCommands: _setupCommands,
      gitHostingProvider: _gitHostingProvider,
    );
  }

  void _setGitHostingProvider(GitHostingProvider? provider) {
    setState(() => _gitHostingProvider = provider);
  }

  void _updateCopyRule(int index, EditableCopyRule rule) {
    setState(() {
      _copyRules = <EditableCopyRule>[
        for (var i = 0; i < _copyRules.length; i += 1)
          if (i == index) rule else _copyRules[i],
      ];
    });
  }

  void _removeCopyRule(int index) {
    setState(() {
      _copyRules = <EditableCopyRule>[
        for (var i = 0; i < _copyRules.length; i += 1)
          if (i != index) _copyRules[i],
      ];
    });
  }

  void _addCopyRule() {
    setState(() {
      _copyRules = <EditableCopyRule>[..._copyRules, const EditableCopyRule()];
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
        _seedSignature = projectConfigSignature(config);
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
        _copyRules = const <EditableCopyRule>[];
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
      gitHostingProvider: _gitHostingProvider,
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
            mouseCursor: SystemMouseCursors.click,
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
