import 'package:alera/src/shared/infra/storage/preferences_store.dart';

class InMemoryStringStore implements StringStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }
}
