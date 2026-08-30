import 'package:alera_mobile/src/features/quotas/application/quota_host_visibility_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('existing installs hide no hosts by default', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(quotaHostVisibilityControllerProvider.future),
      isEmpty,
    );
  });

  test(
    'hidden runtimes survive controller recreation and can be restored',
    () async {
      final first = ProviderContainer();
      await first.read(quotaHostVisibilityControllerProvider.future);
      await first
          .read(quotaHostVisibilityControllerProvider.notifier)
          .setHostVisible('runtime-1', false);
      first.dispose();

      final second = ProviderContainer();
      addTearDown(second.dispose);
      expect(await second.read(quotaHostVisibilityControllerProvider.future), {
        'runtime-1',
      });
      await second
          .read(quotaHostVisibilityControllerProvider.notifier)
          .setHostVisible('runtime-1', true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(quotaHiddenRuntimeIdsKey), isEmpty);
    },
  );

  test('quick edits preserve all hosts and the latest choice', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(
      quotaHostVisibilityControllerProvider.notifier,
    );

    await Future.wait([
      controller.setHostVisible('runtime-1', false),
      controller.setHostVisible('runtime-2', false),
      controller.setHostVisible('runtime-1', true),
      controller.setHostVisible('runtime-3', false),
    ]);

    expect(container.read(quotaHostVisibilityControllerProvider).requireValue, {
      'runtime-2',
      'runtime-3',
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(quotaHiddenRuntimeIdsKey), [
      'runtime-2',
      'runtime-3',
    ]);
  });

  test(
    'edits preserve preferences for temporarily unavailable runtimes',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        quotaHiddenRuntimeIdsKey: ['offline-runtime'],
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(quotaHostVisibilityControllerProvider.notifier)
          .setHostVisible('runtime-1', false);

      expect(
        container.read(quotaHostVisibilityControllerProvider).requireValue,
        {'offline-runtime', 'runtime-1'},
      );
    },
  );
}
