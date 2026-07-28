import 'package:alera/src/features/browser/domain/browser_navigation.dart';

final class BrowserSettings {
  const BrowserSettings({this.searchEngine = BrowserSearchEngine.google});

  factory BrowserSettings.fromJson(Map<String, Object?> json) {
    return BrowserSettings(
      searchEngine: BrowserSearchEngine.values.firstWhere(
        (engine) => engine.name == json['searchEngine'],
        orElse: () => BrowserSearchEngine.google,
      ),
    );
  }

  final BrowserSearchEngine searchEngine;

  Map<String, Object?> toJson() => <String, Object?>{
    'searchEngine': searchEngine.name,
  };
}
