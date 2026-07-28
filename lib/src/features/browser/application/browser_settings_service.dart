import 'package:alera/src/features/browser/domain/browser_settings.dart';

abstract interface class BrowserSettingsService {
  Future<BrowserSettings> get();

  Future<BrowserSettings> set(BrowserSettings settings);
}
