import 'package:alera_mobile/src/features/terminal/application/terminal_clipboard_settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  test('OSC 52 clipboard writes are off until the user opts in', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(terminalClipboardSettingsControllerProvider.future),
      isFalse,
    );

    await container
        .read(terminalClipboardSettingsControllerProvider.notifier)
        .setAllowOsc52Clipboard(true);

    final reloaded = ProviderContainer();
    addTearDown(reloaded.dispose);
    expect(
      await reloaded.read(terminalClipboardSettingsControllerProvider.future),
      isTrue,
    );
  });

  test('stays off when preferences are unavailable', () async {
    SharedPreferencesAsyncPlatform.instance = null;
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      await container.read(terminalClipboardSettingsControllerProvider.future),
      isFalse,
    );
  });
}
