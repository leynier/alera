import 'dart:async';

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:path/path.dart' as p;

class RuntimeProjectManagementClient {
  RuntimeProjectManagementClient(this._client);

  final RuntimeHostClient _client;

  Future<Project> registerProject({required String path, String? name}) async {
    final payload = _asMap(
      await _client.runtimeRequest('project.register', <String, Object?>{
        'path': path,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }),
    );
    return projectFromRuntimeJson(_asMap(payload['project']));
  }

  Future<Project> renameProject({
    required String projectId,
    required String name,
  }) async {
    return projectFromRuntimeJson(
      _asMap(
        await _client.runtimeRequest('project.rename', <String, Object?>{
          'id': projectId,
          'name': name,
        }),
      ),
    );
  }

  Future<void> removeProject(String projectId) {
    return _client.runtimeRequest('project.remove', <String, Object?>{
      'id': projectId,
    });
  }

  Future<Project> cloneProject({
    required String gitUrl,
    required String destinationPath,
    String? name,
  }) async {
    final started = _asMap(
      await _client.runtimeRequest('project.clone.start', <String, Object?>{
        'url': gitUrl,
        'parentPath': p.dirname(destinationPath),
        'directoryName': p.basename(destinationPath),
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }),
    );
    final jobId = started['id'] as String;
    final deadline = DateTime.now().add(const Duration(minutes: 30));
    while (DateTime.now().isBefore(deadline)) {
      final jobs = _asList(await _client.runtimeRequest('project.clone.list'));
      final job = jobs.where((item) => item['id'] == jobId).firstOrNull;
      if (job == null) {
        throw StateError('Clone Job Disappeared: $jobId');
      }
      switch (job['status']) {
        case 'completed':
          final projectId = job['projectId'] as String?;
          final projects = _asList(
            await _client.runtimeRequest('project.list'),
          );
          return projectFromRuntimeJson(
            projects.firstWhere((project) => project['id'] == projectId),
          );
        case 'failed':
          throw StateError(
            (job['error'] as String?) ?? 'Project Clone Failed.',
          );
        case 'cancelled':
          throw StateError('Project Clone Was Cancelled.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw TimeoutException(
      'Project Clone Timed Out.',
      const Duration(minutes: 30),
    );
  }
}

Project projectFromRuntimeJson(Map<String, Object?> json) {
  return Project(
    id: json['id'] as String,
    name: json['name'] as String,
    repoPath: json['repoPath'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    kind: ProjectKind.values.firstWhere(
      (kind) => kind.name == json['kind'],
      orElse: () => ProjectKind.gitRepository,
    ),
  );
}

List<Map<String, Object?>> _asList(Object? value) {
  if (value is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[for (final item in value) _asMap(item)];
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  throw const FormatException('Runtime project payload must be a JSON object.');
}
