import 'package:alera_mobile/src/features/runtime/domain/project_summary.dart';

List<ProjectSummary> sortProjectsForSelection(
  Iterable<ProjectSummary> projects,
) {
  return <ProjectSummary>[...projects]..sort(compareProjectsForSelection);
}

int compareProjectsForSelection(ProjectSummary left, ProjectSummary right) {
  final normalizedOrder = left.name.toLowerCase().compareTo(
    right.name.toLowerCase(),
  );
  if (normalizedOrder != 0) {
    return normalizedOrder;
  }
  final nameOrder = left.name.compareTo(right.name);
  if (nameOrder != 0) {
    return nameOrder;
  }
  return left.id.compareTo(right.id);
}
