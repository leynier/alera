import 'dart:io';

import 'package:alera/src/features/projects/application/project_config_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/features/projects/domain/project_config_paths.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:path/path.dart' as p;
import 'package:toml/toml.dart';

const String aleraProjectConfigFileName = 'alera.toml';

class const TomlProjectConfigFileStore() implements ProjectConfigFileStore {
  @override
  Future<ProjectConfig?> load(Project project) async {
    final file = File(p.join(project.repoPath, aleraProjectConfigFileName));
    if (!await file.exists()) {
      return null;
    }
    try {
      final contents = await file.readAsString();
      return parseProjectConfigToml(contents);
    } on ProjectConfigException {
      rethrow;
    } catch (error) {
      throw ProjectConfigException(
        'Could not load $aleraProjectConfigFileName',
        cause: error,
      );
    }
  }
}

ProjectConfig parseProjectConfigToml(String contents) {
  final Object? decoded;
  try {
    decoded = TomlDocument.parse(contents).toMap();
  } catch (error) {
    throw ProjectConfigException('Invalid alera.toml', cause: error);
  }
  if (decoded is! Map) {
    throw ProjectConfigException('alera.toml must contain a table');
  }
  final root = Map<String, Object?>.from(decoded);
  final provider = _gitHostingProviderFrom(root['git_hosting_provider']);
  final newWorkspace = _newWorkspaceConfigFrom(root['new_workspace']);
  final worktreeValue = root['worktree'];
  if (worktreeValue == null) {
    return ProjectConfig(
      newWorkspace: newWorkspace,
      gitHostingProvider: provider,
    );
  }
  if (worktreeValue is! Map) {
    throw ProjectConfigException('alera.toml [worktree] must be a table');
  }

  final worktree = Map<String, Object?>.from(worktreeValue);
  final copyRules = _copyRulesFrom(worktree['copy']);
  final setup = _setupCommandsFrom(worktree['setup']);
  return ProjectConfig(
    worktree: WorktreeSetupConfig(copy: copyRules, setup: setup),
    newWorkspace: newWorkspace,
    gitHostingProvider: provider,
  );
}

NewWorkspaceConfig _newWorkspaceConfigFrom(Object? value) {
  if (value == null) {
    return NewWorkspaceConfig.defaults;
  }
  if (value is! Map) {
    throw ProjectConfigException('alera.toml [new_workspace] must be a table');
  }
  final table = Map<String, Object?>.from(value);
  final promptAppend = table['prompt_append'];
  if (promptAppend == null) {
    return NewWorkspaceConfig.defaults;
  }
  if (promptAppend is! String) {
    throw ProjectConfigException(
      'new_workspace.prompt_append must be a string',
    );
  }
  return NewWorkspaceConfig(promptAppend: promptAppend.trim());
}

GitHostingProvider? _gitHostingProviderFrom(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw ProjectConfigException('git_hosting_provider must be a string');
  }
  return switch (value.trim().toLowerCase()) {
    'github' ||
    'githubenterprise' ||
    'github_enterprise' ||
    'github-enterprise' => GitHostingProvider.github,
    'azuredevops' ||
    'azure_devops' ||
    'azure-devops' ||
    'azure' => GitHostingProvider.azureDevops,
    'gitlab' || 'git_lab' || 'git-lab' => GitHostingProvider.gitlab,
    _ => throw ProjectConfigException(
      'git_hosting_provider must be one of: github, githubEnterprise, azureDevops, gitlab',
    ),
  };
}

List<WorktreeCopyRule> _copyRulesFrom(Object? value) {
  if (value == null) {
    return const <WorktreeCopyRule>[];
  }
  if (value is! List) {
    throw ProjectConfigException('worktree.copy must be a list');
  }
  final rules = <WorktreeCopyRule>[];
  for (var i = 0; i < value.length; i += 1) {
    final entry = value[i];
    if (entry is! Map) {
      throw ProjectConfigException('worktree.copy[$i] must be a table');
    }
    final table = Map<String, Object?>.from(entry);
    final from = _requiredString(table['from'], 'worktree.copy[$i].from');
    final to = _optionalString(table['to'], 'worktree.copy[$i].to');
    final overwrite = table['overwrite'] ?? false;
    if (overwrite is! bool) {
      throw ProjectConfigException(
        'worktree.copy[$i].overwrite must be a boolean',
      );
    }
    rules.add(
      WorktreeCopyRule(
        from: _validateConfigPath(from, 'worktree.copy[$i].from'),
        to: to == null ? null : _validateConfigPath(to, 'worktree.copy[$i].to'),
        overwrite: overwrite,
      ),
    );
  }
  return List<WorktreeCopyRule>.unmodifiable(rules);
}

List<String> _setupCommandsFrom(Object? value) {
  if (value == null) {
    return const <String>[];
  }
  if (value is! List) {
    throw ProjectConfigException('worktree.setup must be a list');
  }
  final commands = <String>[];
  for (var i = 0; i < value.length; i += 1) {
    final command = _requiredString(value[i], 'worktree.setup[$i]');
    commands.add(command);
  }
  return List<String>.unmodifiable(commands);
}

String _requiredString(Object? value, String label) {
  if (value is! String || value.trim().isEmpty) {
    throw ProjectConfigException('$label must be a non-empty string');
  }
  return value.trim();
}

String? _optionalString(Object? value, String label) {
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw ProjectConfigException('$label must be a non-empty string');
  }
  return value.trim();
}

String _validateConfigPath(String value, String label) {
  try {
    return normalizeProjectConfigPath(value, label);
  } on ProjectConfigPathException catch (error) {
    throw ProjectConfigException(error.message);
  }
}
