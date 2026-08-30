import 'dart:convert';

import 'package:alera/src/features/projects/application/project_config_repository.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart' show Value;

class DriftProjectConfigRepository(final AleraDatabase _db)
    implements ProjectConfigRepository {
  @override
  Future<ProjectConfig?> findByProjectId(String projectId) async {
    final row = await (_db.select(
      _db.projectConfigsTable,
    )..where((table) => table.projectId.equals(projectId))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _configFromJson(row.dataJson);
  }

  @override
  Future<Map<String, ProjectConfig>> loadAll() async {
    final rows = await _db.select(_db.projectConfigsTable).get();
    return <String, ProjectConfig>{
      for (final row in rows) row.projectId: _configFromJson(row.dataJson),
    };
  }

  @override
  Stream<Map<String, ProjectConfig>> watchAll() {
    return _db.select(_db.projectConfigsTable).watch().map((rows) {
      return <String, ProjectConfig>{
        for (final row in rows) row.projectId: _configFromJson(row.dataJson),
      };
    });
  }

  @override
  Future<void> save({
    required String projectId,
    required ProjectConfig config,
    required DateTime updatedAt,
  }) async {
    await _db
        .into(_db.projectConfigsTable)
        .insertOnConflictUpdate(
          ProjectConfigsTableCompanion(
            projectId: Value(projectId),
            dataJson: Value(jsonEncode(config.toMap())),
            updatedAt: Value(updatedAt.toUtc()),
          ),
        );
  }

  @override
  Future<void> remove(String projectId) async {
    await (_db.delete(
      _db.projectConfigsTable,
    )..where((table) => table.projectId.equals(projectId))).go();
  }
}

ProjectConfig _configFromJson(String dataJson) {
  final decoded = jsonDecode(dataJson);
  if (decoded is! Map) {
    return ProjectConfig.empty;
  }
  return ProjectConfig.fromJson(Map<String, Object?>.from(decoded));
}
