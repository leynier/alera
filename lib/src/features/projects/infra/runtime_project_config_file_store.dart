import 'package:alera/src/features/projects/application/project_config_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class RuntimeProjectConfigFileStore implements ProjectConfigFileStore {
  const RuntimeProjectConfigFileStore(this._client);

  final RuntimeHostClient _client;

  @override
  Future<ProjectConfig?> load(Project project) async {
    final payload = _asMap(
      await _client.runtimeRequest('projectConfig.effective', <String, Object?>{
        'projectId': project.id,
      }),
    );
    if (payload['origin'] != 'repoFile') return null;
    final error = payload['error'] as String?;
    if (error != null && error.isNotEmpty) {
      throw ProjectConfigException(error);
    }
    return ProjectConfig.fromJson(_asMap(payload['config']));
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  throw const FormatException('Runtime project config must be a JSON object.');
}
