import 'package:shared_preferences/shared_preferences.dart';

abstract interface class StringStore {
  Future<void> setString(String key, String value);
  Future<String?> getString(String key);
  Future<void> remove(String key);
}

class PreferencesStore implements StringStore {
  const PreferencesStore(this._preferences);

  final SharedPreferencesAsync _preferences;

  @override
  Future<void> setString(String key, String value) {
    return _preferences.setString(key, value);
  }

  Future<void> setStringList(String key, List<String> values) {
    return _preferences.setStringList(key, values);
  }

  @override
  Future<String?> getString(String key) {
    return _preferences.getString(key);
  }

  Future<List<String>?> getStringList(String key) {
    return _preferences.getStringList(key);
  }

  @override
  Future<void> remove(String key) {
    return _preferences.remove(key);
  }
}

class InMemoryPreferencesStore implements StringStore {
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
