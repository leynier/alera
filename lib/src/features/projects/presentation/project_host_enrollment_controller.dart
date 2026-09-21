import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter/widgets.dart';

/// Adds [project] to [hostId] and answers the project as the runtime now
/// reports it. A blank [existingPath] asks the host to clone the project.
typedef AddProjectToHost = Future<Project> Function(
  Project project,
  String hostId,
  String? existingPath,
);

/// State of one "Add to Host" form. It lives outside the form widget because
/// a clone can take minutes: the form may scroll away or be rebuilt for
/// another host while the request is still running, and the owner still has to
/// know that it is.
class ProjectHostEnrollmentController extends ChangeNotifier {
  ProjectHostEnrollmentController(this._addProjectToHost);

  final AddProjectToHost? _addProjectToHost;
  final TextEditingController pathController = TextEditingController();
  final Map<String, Project> _refreshedProjects = <String, Project>{};
  bool _adding = false;
  bool _disposed = false;
  String? _error;

  /// False when the runtime cannot put a project on more hosts.
  bool get supported => _addProjectToHost != null;

  bool get adding => _adding;

  String? get error => _error;

  /// The latest known version of [project]; the one a finished add returned
  /// wins over the list the owner was opened with.
  Project resolve(Project project) => _refreshedProjects[project.id] ?? project;

  void clearError() {
    if (_error == null) {
      return;
    }
    _error = null;
    _notify();
  }

  /// Returns the refreshed project, or null when the add failed; the reason
  /// is then in [error].
  Future<Project?> add(Project project, String hostId) async {
    final addProjectToHost = _addProjectToHost;
    if (addProjectToHost == null || _adding) {
      return null;
    }
    _adding = true;
    _error = null;
    _notify();
    try {
      final path = pathController.text.trim();
      final refreshed = await addProjectToHost(
        project,
        hostId,
        path.isEmpty ? null : path,
      );
      _refreshedProjects[project.id] = refreshed;
      if (!_disposed) {
        pathController.clear();
      }
      return refreshed;
    } catch (error) {
      _error = userFacingExceptionMessage(error);
      return null;
    } finally {
      _adding = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    pathController.dispose();
    super.dispose();
  }
}
