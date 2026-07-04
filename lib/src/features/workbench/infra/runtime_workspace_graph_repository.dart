import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class RuntimeWorkspaceGraphRepository implements WorkspaceGraphRepository {
  RuntimeWorkspaceGraphRepository(this._client, {this.beforeAccess});

  final RuntimeHostClient _client;
  final Future<void> Function()? beforeAccess;

  @override
  Future<List<WorkspaceTag>> listTags() async {
    await _ensureReady();
    final payload = await _client.runtimeRequest('workspaceTag.list');
    return _asList(payload).map(WorkspaceTag.fromJson).toList(growable: false);
  }

  @override
  Future<WorkspaceTag> upsertTag(WorkspaceTag tag) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'workspaceTag.upsert',
      tag.toJson(),
    );
    return WorkspaceTag.fromJson(_asMap(payload));
  }

  @override
  Future<void> removeTag(String tagId) async {
    await _ensureReady();
    await _client.runtimeRequest('workspaceTag.remove', <String, Object?>{
      'id': tagId,
    });
  }

  @override
  Future<void> assignTag({
    required String workspaceId,
    required String tagId,
  }) async {
    await _ensureReady();
    await _client.runtimeRequest('workspaceTag.assign', <String, Object?>{
      'workspaceId': workspaceId,
      'tagId': tagId,
    });
  }

  @override
  Future<void> unassignTag({
    required String workspaceId,
    required String tagId,
  }) async {
    await _ensureReady();
    await _client.runtimeRequest('workspaceTag.unassign', <String, Object?>{
      'workspaceId': workspaceId,
      'tagId': tagId,
    });
  }

  @override
  Future<List<WorkspaceRelation>> listRelations() async {
    await _ensureReady();
    final payload = await _client.runtimeRequest('workspaceRelation.list');
    return _asList(
      payload,
    ).map(WorkspaceRelation.fromJson).toList(growable: false);
  }

  @override
  Future<WorkspaceRelation> linkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    await _ensureReady();
    final payload = await _client.runtimeRequest(
      'workspaceRelation.link',
      <String, Object?>{
        'parentWorkspaceId': parentWorkspaceId,
        'childWorkspaceId': childWorkspaceId,
      },
    );
    return WorkspaceRelation.fromJson(_asMap(payload));
  }

  @override
  Future<void> unlinkWorkspaces({
    required String parentWorkspaceId,
    required String childWorkspaceId,
  }) async {
    await _ensureReady();
    await _client.runtimeRequest('workspaceRelation.unlink', <String, Object?>{
      'parentWorkspaceId': parentWorkspaceId,
      'childWorkspaceId': childWorkspaceId,
    });
  }

  Future<void> _ensureReady() async {
    final callback = beforeAccess;
    if (callback != null) {
      await callback();
    }
  }
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
  throw const FormatException('Workspace graph payload must be a JSON object.');
}
