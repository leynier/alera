import 'package:alera/src/features/browser/application/browser_settings_service.dart';
import 'package:alera/src/features/browser/domain/browser_settings.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_payload.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

final class RuntimeBrowserSettingsService implements BrowserSettingsService {
  const RuntimeBrowserSettingsService(this._client);

  final RuntimeHostClient _client;

  @override
  Future<BrowserSettings> get() async {
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest('browser.settings.get'),
      'Browser settings read',
    );
    return BrowserSettings.fromJson(
      browserRuntimeItem(response['settings'], 'Browser settings'),
    );
  }

  @override
  Future<BrowserSettings> set(BrowserSettings settings) async {
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest('browser.settings.set', settings.toJson()),
      'Browser settings update',
    );
    return BrowserSettings.fromJson(
      browserRuntimeItem(response['settings'], 'Browser settings'),
    );
  }
}
