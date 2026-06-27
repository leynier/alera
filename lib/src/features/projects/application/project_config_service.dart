import 'package:alera/src/features/projects/application/project_config_repository.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';

enum ProjectConfigOrigin { none, repoFile, uiOverride }

class EffectiveProjectConfig {
  const EffectiveProjectConfig({
    required this.config,
    required this.origin,
    this.error,
  });

  final ProjectConfig config;
  final ProjectConfigOrigin origin;
  final Object? error;

  bool get hasError => error != null;

  static const empty = EffectiveProjectConfig(
    config: ProjectConfig.empty,
    origin: ProjectConfigOrigin.none,
  );
}

abstract interface class ProjectConfigReader {
  Future<EffectiveProjectConfig> resolve(Project project);
}

class NoopProjectConfigReader implements ProjectConfigReader {
  const NoopProjectConfigReader();

  @override
  Future<EffectiveProjectConfig> resolve(Project project) async {
    return EffectiveProjectConfig.empty;
  }
}

abstract interface class ProjectConfigFileStore {
  Future<ProjectConfig?> load(Project project);
}

class ProjectConfigException implements Exception {
  ProjectConfigException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    if (cause == null) {
      return message;
    }
    return '$message: $cause';
  }
}

class ProjectConfigService implements ProjectConfigReader {
  ProjectConfigService({
    required ProjectConfigRepository repository,
    required ProjectConfigFileStore fileStore,
    DateTime Function()? now,
  }) : this._(repository, fileStore, now ?? DateTime.now);

  ProjectConfigService._(this._repository, this._fileStore, this._now);

  final ProjectConfigRepository _repository;
  final ProjectConfigFileStore _fileStore;
  final DateTime Function() _now;

  Future<ProjectConfig?> findUiOverride(String projectId) {
    return _repository.findByProjectId(projectId);
  }

  Future<Map<String, ProjectConfig>> loadUiOverrides() {
    return _repository.loadAll();
  }

  Stream<Map<String, ProjectConfig>> watchUiOverrides() {
    return _repository.watchAll();
  }

  Future<ProjectConfig?> loadRepoFile(Project project) {
    return _fileStore.load(project);
  }

  Future<void> saveUiOverride({
    required String projectId,
    required ProjectConfig config,
  }) {
    return _repository.save(
      projectId: projectId,
      config: config,
      updatedAt: _now().toUtc(),
    );
  }

  Future<void> removeUiOverride(String projectId) {
    return _repository.remove(projectId);
  }

  @override
  Future<EffectiveProjectConfig> resolve(Project project) async {
    final override = await _repository.findByProjectId(project.id);
    if (override != null) {
      return EffectiveProjectConfig(
        config: override,
        origin: ProjectConfigOrigin.uiOverride,
      );
    }

    try {
      final repoConfig = await _fileStore.load(project);
      if (repoConfig != null) {
        return EffectiveProjectConfig(
          config: repoConfig,
          origin: ProjectConfigOrigin.repoFile,
        );
      }
    } catch (error) {
      return EffectiveProjectConfig(
        config: ProjectConfig.empty,
        origin: ProjectConfigOrigin.repoFile,
        error: error,
      );
    }

    return EffectiveProjectConfig.empty;
  }
}
