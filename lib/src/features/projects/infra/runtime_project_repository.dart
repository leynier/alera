import 'dart:async';

import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/infra/runtime_project_management_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

class RuntimeProjectRepository implements ProjectRepository {
  RuntimeProjectRepository(
    this._client, {
    this.beforeAccess,
    RuntimeChangeCoalescer? coalescer,
  }) : _coalescer = coalescer ?? RuntimeChangeCoalescer();

  final RuntimeHostClient _client;
  final Future<void> Function()? beforeAccess;
  final RuntimeChangeCoalescer _coalescer;

  @override
  Future<List<Project>> listAll() async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'project.list',
      const <String, Object?>{},
      runtimeSnapshotRequestTimeout,
    );
    return _asList(payload).map(projectFromRuntimeJson).toList(growable: false);
  }

  @override
  Stream<List<Project>> watchAll() {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: const <String>{'projectsChanged'},
      readSnapshot: listAll,
      coalesceKey: 'projects',
      coalescer: _coalescer,
    );
  }

  @override
  Future<Project> add(Project project) {
    return _upsert(project);
  }

  @override
  Future<Project> update(Project project) {
    return _upsert(project);
  }

  Future<Project> _upsert(Project project) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'project.upsert',
      _projectToJson(project),
    );
    return projectFromRuntimeJson(_asMap(payload));
  }

  @override
  Future<void> remove(String projectId) async {
    await _ensureReady();
    await _client.runtimeRequest('project.remove', <String, Object?>{
      'id': projectId,
    });
  }

  Future<void> _ensureReady() async {
    final callback = beforeAccess;
    if (callback != null) {
      await callback();
    }
  }
}

Map<String, Object?> _projectToJson(Project project) {
  return <String, Object?>{
    'id': project.id,
    'name': project.name,
    'repoPath': project.repoPath,
    'createdAt': project.createdAt.toUtc().toIso8601String(),
    'updatedAt': project.updatedAt.toUtc().toIso8601String(),
    'kind': project.kind.name,
  };
}

List<Map<String, Object?>> _asList(Object? value) {
  if (value is List) {
    return <Map<String, Object?>>[for (final item in value) _asMap(item)];
  }
  return const <Map<String, Object?>>[];
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw const FormatException('Runtime project payload must be a JSON object.');
}
