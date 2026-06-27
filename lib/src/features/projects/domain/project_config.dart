import 'package:dart_mappable/dart_mappable.dart';

part 'project_config.mapper.dart';

@MappableClass()
class ProjectConfig with ProjectConfigMappable {
  const ProjectConfig({this.worktree = WorktreeSetupConfig.defaults});

  final WorktreeSetupConfig worktree;

  bool get isEmpty => worktree.isEmpty;

  static const ProjectConfig empty = ProjectConfig();

  factory ProjectConfig.fromJson(Map<String, Object?> json) =>
      ProjectConfigMapper.fromMap(Map<String, dynamic>.from(json));
}

@MappableClass()
class WorktreeSetupConfig with WorktreeSetupConfigMappable {
  const WorktreeSetupConfig({
    this.copy = const <WorktreeCopyRule>[],
    this.setup = const <String>[],
  });

  final List<WorktreeCopyRule> copy;
  final List<String> setup;

  bool get isEmpty => copy.isEmpty && setup.isEmpty;

  static const WorktreeSetupConfig defaults = WorktreeSetupConfig();
}

@MappableClass()
class WorktreeCopyRule with WorktreeCopyRuleMappable {
  const WorktreeCopyRule({required this.from, this.to, this.overwrite = false});

  final String from;
  final String? to;
  final bool overwrite;

  String get destination => to ?? from;
}
