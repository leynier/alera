import 'package:alera/src/features/keep_alive/application/keep_alive_providers.dart';
import 'package:alera/src/features/keep_alive/domain/keep_alive_snapshot.dart';
import 'package:alera/src/features/keep_alive/infra/keep_alive_backend.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/application/settings_providers.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeepAliveController', () {
    test('toggle persists keep-alive when the lock starts', () async {
      final backend = _FakeKeepAliveBackend();
      final repository = _MemorySettingsRepository();
      final container = ProviderContainer(
        overrides: [
          keepAliveBackendProvider.overrideWithValue(backend),
          settingsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      container.read(keepAliveControllerProvider);
      await container.read(keepAliveControllerProvider.notifier).toggle();

      expect(backend.enabled, isTrue);
      expect(container.read(keepAliveControllerProvider).active, isTrue);
      expect(
        container.read(settingsControllerProvider).general.keepAliveEnabled,
        isTrue,
      );
      expect((await repository.load()).general.keepAliveEnabled, isTrue);
    });

    test('toggle does not persist when the lock fails to start', () async {
      final backend = _FakeKeepAliveBackend()..failWith = 'not supported';
      final repository = _MemorySettingsRepository();
      final container = ProviderContainer(
        overrides: [
          keepAliveBackendProvider.overrideWithValue(backend),
          settingsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      container.read(keepAliveControllerProvider);
      await container.read(keepAliveControllerProvider.notifier).toggle();

      expect(backend.enabled, isFalse);
      expect(container.read(keepAliveControllerProvider).active, isFalse);
      expect(container.read(keepAliveControllerProvider).hasError, isTrue);
      expect(
        container.read(settingsControllerProvider).general.keepAliveEnabled,
        isFalse,
      );
    });
  });
}

class _FakeKeepAliveBackend implements KeepAliveBackend {
  bool enabled = false;
  String? failWith;

  @override
  Future<KeepAliveSnapshot> setEnabled(bool enabled) async {
    if (enabled && failWith != null) {
      return KeepAliveSnapshot.inactive(error: failWith);
    }
    this.enabled = enabled;
    if (enabled) {
      return const KeepAliveSnapshot.active();
    }
    return const KeepAliveSnapshot.inactive();
  }

  @override
  Future<KeepAliveSnapshot> status() async {
    if (enabled) {
      return const KeepAliveSnapshot.active();
    }
    return const KeepAliveSnapshot.inactive();
  }
}

class _MemorySettingsRepository implements SettingsRepository {
  AleraSettings _settings = AleraSettings.defaults;

  @override
  Future<AleraSettings> load() async => _settings;

  @override
  Future<void> save(AleraSettings settings) async {
    _settings = settings;
  }
}
