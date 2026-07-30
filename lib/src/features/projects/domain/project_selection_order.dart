import 'package:alera/src/features/projects/domain/project.dart';

List<Project> sortProjectsForSelection(Iterable<Project> projects) {
  return <Project>[...projects]..sort(compareProjectsForSelection);
}

int compareProjectsForSelection(Project left, Project right) {
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
