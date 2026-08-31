import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/features/settings/presentation/panes/project_config_editor.dart';
import 'package:flutter/material.dart';

class const ProjectConfigEditorLoader({
  super.key,
  required final Project project,
  required final ProjectConfig? overrideConfig,
  required final Future<ProjectConfig?> repoConfigFuture,
  required final String? saveError,
  required final bool saving,
  required final ({
    List<EditableCopyRule> copyRules,
    List<String> setupCommands,
    String promptAppend,
    GitHostingProvider? gitHostingProvider,
  })
  Function({required Project project, required ProjectConfig config})
  seedEditor,
  required final void Function(int index, EditableCopyRule rule) updateCopyRule,
  required final ValueChanged<int> removeCopyRule,
  required final VoidCallback addCopyRule,
  required final void Function(int index, String command) updateSetupCommand,
  required final ValueChanged<int> removeSetupCommand,
  required final VoidCallback addSetupCommand,
  required final ValueChanged<String> onPromptAppendChanged,
  required final Future<void> Function(Project project) saveOverride,
  required final Future<void> Function()? useRepoFile,
  required final ValueChanged<GitHostingProvider?> onGitHostingProviderChanged,
}) extends StatelessWidget {
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
          final editorState = seedEditor(project: project, config: .empty);
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
