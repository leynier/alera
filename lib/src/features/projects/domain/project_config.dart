import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:dart_mappable/dart_mappable.dart';

part 'project_config.mapper.dart';

@MappableClass()
class const ProjectConfig({
  this.worktree = WorktreeSetupConfig.defaults,
  this.newWorkspace = NewWorkspaceConfig.defaults,
  this.gitHostingProvider,
}) with ProjectConfigMappable {
  final WorktreeSetupConfig worktree;
  final NewWorkspaceConfig newWorkspace;

  /// Overrides auto-detection of the git hosting provider for this project.
  /// Null means auto-detect from the repository's remote.
  final GitHostingProvider? gitHostingProvider;

  bool get isEmpty =>
      worktree.isEmpty && newWorkspace.isEmpty && gitHostingProvider == null;

  static const ProjectConfig empty = ProjectConfig();

  factory fromJson(Map<String, Object?> json) =>
      ProjectConfigMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class const NewWorkspaceConfig({this.promptAppend = ''})
    with NewWorkspaceConfigMappable {
  final String promptAppend;

  bool get isEmpty => promptAppend.trim().isEmpty;

  static const NewWorkspaceConfig defaults = NewWorkspaceConfig();
}

@MappableClass()
class const WorktreeSetupConfig({
  this.copy = const <WorktreeCopyRule>[],
  this.setup = const <String>[],
}) with WorktreeSetupConfigMappable {
  final List<WorktreeCopyRule> copy;
  final List<String> setup;

  bool get isEmpty => copy.isEmpty && setup.isEmpty;

  static const WorktreeSetupConfig defaults = WorktreeSetupConfig();
}

@MappableClass()
class const WorktreeCopyRule({
  required this.from,
  this.to,
  this.overwrite = false,
}) with WorktreeCopyRuleMappable {
  final String from;
  final String? to;
  final bool overwrite;

  String get destination => to ?? from;
}
