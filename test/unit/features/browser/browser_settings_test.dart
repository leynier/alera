import 'package:alera/src/features/browser/domain/browser_navigation.dart';
import 'package:alera/src/features/browser/domain/browser_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings round-trip supported search engines', () {
    final settings = BrowserSettings.fromJson(<String, Object?>{
      'searchEngine': 'kagi',
    });

    expect(settings.searchEngine, BrowserSearchEngine.kagi);
    expect(settings.toJson(), <String, Object?>{'searchEngine': 'kagi'});
  });

  test('settings fall back to Google for unknown search engines', () {
    final settings = BrowserSettings.fromJson(<String, Object?>{
      'searchEngine': 'future-search',
    });

    expect(settings.searchEngine, BrowserSearchEngine.google);
  });
}
