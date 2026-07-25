import 'dart:async';

import 'package:alera/src/features/projects/application/project_config_repository.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

class RuntimeProjectConfigRepository implements ProjectConfigRepository {
  RuntimeProjectConfigRepository(
    this._client, {
    this.beforeAccess,
    RuntimeChangeCoalescer? coalescer,
  }) : _coalescer = coalescer ?? RuntimeChangeCoalescer();

  final RuntimeHostClient _client;
  final Future<void> Function()? beforeAccess;
  final RuntimeChangeCoalescer _coalescer;

  @override
  Future<ProjectConfig?> findByProjectId(String projectId) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'projectConfig.find',
      <String, Object?>{'projectId': projectId},
    );
    if (payload == null) {
      return null;
    }
    return ProjectConfig.fromJson(_asMap(payload));
  }

  @override
  Future<Map<String, ProjectConfig>> loadAll() async {
    await _ensureReady();
    final payload = await _client.runtimeRequest('projectConfig.list');
    final map = _asMap(payload);
    return <String, ProjectConfig>{
      for (final entry in map.entries)
        entry.key: ProjectConfig.fromJson(_asMap(entry.value)),
    };
  }

  @override
  Stream<Map<String, ProjectConfig>> watchAll() {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: const <String>{'projectConfigsChanged'},
      readSnapshot: loadAll,
      coalesceKey: 'projectConfigs',
      coalescer: _coalescer,
    );
  }

  @override
  Future<void> save({
    required String projectId,
    required ProjectConfig config,
    required DateTime updatedAt,
  }) async {
    await _ensureReady();
    await _client.runtimeRequest('projectConfig.upsert', <String, Object?>{
      'projectId': projectId,
      'config': config.toMap(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    });
  }

  @override
  Future<void> remove(String projectId) async {
    await _ensureReady();
    await _client.runtimeRequest('projectConfig.remove', <String, Object?>{
      'projectId': projectId,
    });
  }

  Future<void> _ensureReady() async {
    final callback = beforeAccess;
    if (callback != null) {
      await callback();
    }
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw const FormatException(
    'Runtime project config payload must be a JSON object.',
  );
}
