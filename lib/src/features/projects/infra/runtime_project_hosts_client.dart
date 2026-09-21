import 'package:alera/src/features/projects/domain/project.dart';

/// Adding a project to a host can clone a repository, so the request outlives
/// an ordinary runtime call.
const Duration projectHostAddTimeout = Duration(minutes: 30);

/// One host a project is on, as `project.hosts.list` reports it.
class const ProjectHost({
  required final String hostId,
  required final String path,
  required final bool primary,
  required final int workspaceCount,
});

/// The runtime's `project.hosts.*` verbs: one project registered on several
/// hosts. `add` without a path asks the host to clone the project's Git remote
/// into its own default projects folder; `remove` forgets the checkout and
/// never deletes files.
class RuntimeProjectHostsClient(
  final Future<Object?> Function(
    String type,
    Map<String, Object?> payload,
    Duration? timeout,
  )
  request,
) {
  Future<List<ProjectHost>> list(String projectId) async {
    return _hosts(
      await request('project.hosts.list', {'projectId': projectId}, null),
    );
  }

  Future<ProjectCheckout> add({
    required String projectId,
    required String hostId,
    String? path,
    String? cloneUrl,
  }) async {
    final value = await request('project.hosts.add', {
      'projectId': projectId,
      'hostId': hostId,
      if (path != null && path.trim().isNotEmpty) 'path': path.trim(),
      if (cloneUrl != null && cloneUrl.trim().isNotEmpty)
        'cloneUrl': cloneUrl.trim(),
    }, projectHostAddTimeout);
    if (value is! Map ||
        value['hostId'] is! String ||
        value['path'] is! String) {
      throw StateError('Update the runtime to add projects to hosts.');
    }
    return ProjectCheckout(
      hostId: value['hostId']! as String,
      path: value['path']! as String,
    );
  }

  Future<List<ProjectHost>> remove({
    required String projectId,
    required String hostId,
  }) async {
    return _hosts(
      await request('project.hosts.remove', {
        'projectId': projectId,
        'hostId': hostId,
      }, null),
    );
  }

  static List<ProjectHost> _hosts(Object? value) {
    if (value is! Map || value['hosts'] is! List) {
      throw StateError('Update the runtime to manage project hosts.');
    }
    return List<ProjectHost>.unmodifiable(<ProjectHost>[
      for (final host in value['hosts']! as List)
        if (host is Map && host['hostId'] is String && host['path'] is String)
          ProjectHost(
            hostId: host['hostId']! as String,
            path: host['path']! as String,
            primary: host['primary'] == true,
            workspaceCount: host['workspaceCount'] is num
                ? (host['workspaceCount']! as num).toInt()
                : 0,
          ),
    ]);
  }
}
