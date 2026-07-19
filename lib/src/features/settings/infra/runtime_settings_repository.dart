import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class RuntimeSettingsRepository implements SettingsRepository {
  RuntimeSettingsRepository({
    required this.client,
    required this.legacyRepository,
    this.beforeAccess,
  });

  final RuntimeHostClient client;
  final SettingsRepository legacyRepository;
  final Future<void> Function()? beforeAccess;

  @override
  Future<AleraSettings> load() async {
    final legacy = await legacyRepository.load();
    try {
      await beforeAccess?.call();
      final payload = await client.runtimeRequest('runtimeSettings.get');
      final runtime = _asMap(payload);
      if (!runtime.containsKey('workspaceDirectory')) {
        return legacy;
      }
      return legacy.copyWith(
        general: legacy.general.copyWith(
          workspaceDirectory: runtime['workspaceDirectory'] as String?,
          confirmWorkspaceRemoval:
              runtime['confirmWorkspaceRemoval'] as bool? ??
              legacy.general.confirmWorkspaceRemoval,
        ),
        agents: legacy.agents.copyWith(
          agentStatusHooks: AgentStatusHookSettings.fromJson(
            _asMap(runtime['agentStatusHooks']),
          ),
        ),
      );
    } catch (_) {
      return legacy;
    }
  }

  @override
  Future<void> save(AleraSettings settings) async {
    await legacyRepository.save(settings);
    await beforeAccess?.call();
    await client.runtimeRequest('runtimeSettings.update', <String, Object?>{
      'workspaceDirectory': settings.general.workspaceDirectory,
      'confirmWorkspaceRemoval': settings.general.confirmWorkspaceRemoval,
      'agentStatusHooks': settings.agents.agentStatusHooks.toJson(),
    });
  }
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return const <String, Object?>{};
}
