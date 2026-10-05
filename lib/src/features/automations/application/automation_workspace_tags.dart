import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'automation_workspace_tags.g.dart';

/// Workspace tags an automation can give the workspaces its runs create.
@riverpod
Future<List<WorkspaceTag>> automationWorkspaceTags(Ref ref) =>
    ref.read(workbenchControllerProvider.notifier).listWorkspaceTags();

/// Names of [ids], in order, for the tags that still exist.
String automationWorkspaceTagNames(
  List<String> ids,
  List<WorkspaceTag>? tags,
) => <String>[
  for (final id in ids)
    if (tags?.where((tag) => tag.id == id).firstOrNull case final tag?)
      tag.name,
].join(', ');
