import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/runtime_settings_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'RuntimeSettingsRepository sends structured portable settings',
    () async {
      final client = _RecordingRuntimeHostClient();
      final repository = RuntimeSettingsRepository(
        client: client,
        legacyRepository: _MemorySettingsRepository(),
      );

      await repository.save(AleraSettings.defaults);

      final payload = client.payloads['runtimeSettings.update']!.single;
      expect(payload['agentStatusHooks'], isA<Map<String, Object?>>());
      expect(payload['agentQuotas'], isA<Map<String, Object?>>());
      expect(
        (payload['agentQuotas']! as Map<String, Object?>)['enabledProviders'],
        <String>[
          'claude',
          'codex',
          'kimi',
          'grok',
          'antigravity',
          'minimax',
          'zai',
        ],
      );
    },
  );
}

final class _RecordingRuntimeHostClient implements RuntimeHostClient {
  final payloads = <String, List<Map<String, Object?>>>{};

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    payloads.putIfAbsent(type, () => <Map<String, Object?>>[]).add(payload);
    return null;
  }
}

final class _MemorySettingsRepository implements SettingsRepository {
  AleraSettings settings = AleraSettings.defaults;

  @override
  Future<AleraSettings> load() async => settings;

  @override
  Future<void> save(AleraSettings settings) async {
    this.settings = settings;
  }
}
