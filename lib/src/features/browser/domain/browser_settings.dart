import 'package:alera/src/features/browser/domain/browser_navigation.dart';

final class const BrowserSettings({
  final BrowserSearchEngine searchEngine = BrowserSearchEngine.google,
}) {
  factory fromJson(Map<String, Object?> json) {
    return BrowserSettings(
      searchEngine: BrowserSearchEngine.values.firstWhere(
        (engine) => engine.name == json['searchEngine'],
        orElse: () => BrowserSearchEngine.google,
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'searchEngine': searchEngine.name,
  };
}
