import 'package:alera/src/features/workbench/domain/workspace_section.dart';

class WorkspaceSectionSnapshot {
  const WorkspaceSectionSnapshot({
    required this.supported,
    this.sections = const [],
  });

  final bool supported;
  final List<WorkspaceSection> sections;
}

abstract interface class WorkspaceSectionRepository {
  Future<bool> supportsSections();
  Stream<WorkspaceSectionSnapshot> watchSections();
  Future<List<WorkspaceSection>> listSections();
  Future<void> createSection(String name, String workspaceId);
  Future<void> setSection(String workspaceId, String? sectionId);
  Future<void> removeSection(String sectionId);
}
