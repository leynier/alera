import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/features/settings/presentation/panes/project_config_editor.dart';
import 'package:flutter/material.dart';

class ProjectConfigEditorLoader extends StatelessWidget {
  const ProjectConfigEditorLoader({
    super.key,
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
    required this.onPromptAppendChanged,
    required this.saveOverride,
    required this.useRepoFile,
    required this.onGitHostingProviderChanged,
  });

  final Project project;
  final ProjectConfig? overrideConfig;
  final Future<ProjectConfig?> repoConfigFuture;
  final String? saveError;
  final bool saving;
  final ({
    List<EditableCopyRule> copyRules,
    List<String> setupCommands,
    String promptAppend,
    GitHostingProvider? gitHostingProvider,
  })
  Function({required Project project, required ProjectConfig config})
  seedEditor;
  final ValueChanged<GitHostingProvider?> onGitHostingProviderChanged;
  final void Function(int index, EditableCopyRule rule) updateCopyRule;
  final ValueChanged<int> removeCopyRule;
  final VoidCallback addCopyRule;
  final void Function(int index, String command) updateSetupCommand;
  final ValueChanged<int> removeSetupCommand;
  final VoidCallback addSetupCommand;
  final ValueChanged<String> onPromptAppendChanged;
  final Future<void> Function(Project project) saveOverride;
  final Future<void> Function()? useRepoFile;

  @override
  Widget build(BuildContext context) {
    final override = overrideConfig;
    if (override != null) {
      final editorState = seedEditor(project: project, config: override);
      return ProjectConfigEditor(
        project: project,
        sourceLabel: 'UI Override',
        gitHostingProvider: editorState.gitHostingProvider,
        onGitHostingProviderChanged: onGitHostingProviderChanged,
        copyRules: editorState.copyRules,
        setupCommands: editorState.setupCommands,
        promptAppend: editorState.promptAppend,
        onPromptAppendChanged: onPromptAppendChanged,
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
          return ProjectConfigEditor(
            project: project,
            sourceLabel: 'Repo file error',
            sourceError: snapshot.error.toString(),
            gitHostingProvider: editorState.gitHostingProvider,
            onGitHostingProviderChanged: onGitHostingProviderChanged,
            copyRules: editorState.copyRules,
            setupCommands: editorState.setupCommands,
            promptAppend: editorState.promptAppend,
            onPromptAppendChanged: onPromptAppendChanged,
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
        return ProjectConfigEditor(
          project: project,
          sourceLabel: repoConfig == null ? 'None' : 'Repo file',
          gitHostingProvider: editorState.gitHostingProvider,
          onGitHostingProviderChanged: onGitHostingProviderChanged,
          copyRules: editorState.copyRules,
          setupCommands: editorState.setupCommands,
          promptAppend: editorState.promptAppend,
          onPromptAppendChanged: onPromptAppendChanged,
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
