import 'dart:async';

import 'package:alera/src/features/projects/application/project_config_repository.dart';
import 'package:alera/src/features/projects/application/project_config_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';

class FakeProjectConfigRepository implements ProjectConfigRepository {
  final Map<String, ProjectConfig> configs = <String, ProjectConfig>{};
  final StreamController<Map<String, ProjectConfig>> _controller =
      StreamController<Map<String, ProjectConfig>>.broadcast();

  @override
  Future<ProjectConfig?> findByProjectId(String projectId) async {
    return configs[projectId];
  }

  @override
  Future<Map<String, ProjectConfig>> loadAll() async {
    return Map<String, ProjectConfig>.unmodifiable(configs);
  }

  @override
  Stream<Map<String, ProjectConfig>> watchAll() async* {
    yield Map<String, ProjectConfig>.unmodifiable(configs);
    yield* _controller.stream;
  }

  @override
  Future<void> save({
    required String projectId,
    required ProjectConfig config,
    required DateTime updatedAt,
  }) async {
    configs[projectId] = config;
    _emit();
  }

  @override
  Future<void> remove(String projectId) async {
    configs.remove(projectId);
    _emit();
  }

  void dispose() {
    unawaited(_controller.close());
  }

  void _emit() {
    _controller.add(Map<String, ProjectConfig>.unmodifiable(configs));
  }
}

class FakeProjectConfigFileStore({var ProjectConfig? config})
    implements ProjectConfigFileStore {
  Object? error;

  @override
  Future<ProjectConfig?> load(Project project) async {
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return config;
  }
}
