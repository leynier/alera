import 'dart:convert';

import 'package:alera_mobile/src/features/configuration_sync/infra/mobile_configuration_preferences.dart';

import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_preferences_repository.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalMobileCodexPreferencesRepository
    implements MobileCodexPreferencesRepository {
  LocalMobileCodexPreferencesRepository({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<MobileCodexPreferences> load(String hostId) =>
      MobileConfigurationPreferences.transaction((_) async {
        final encoded =
            await _preferences.getString(_key(hostId)) ??
            await _preferences.getString('alera.mobile.codex.defaults');
        if (encoded == null || encoded.isEmpty) {
          return const MobileCodexPreferences();
        }
        final decoded = jsonDecode(encoded);
        return decoded is Map
            ? MobileCodexPreferences.fromJson(
                Map<String, Object?>.from(decoded),
              )
            : const MobileCodexPreferences();
      }, preferences: _preferences);

  @override
  Future<void> save(String hostId, MobileCodexPreferences preferences) =>
      MobileConfigurationPreferences.transaction((prefs) async {
        await prefs.setString(_key(hostId), jsonEncode(preferences.toJson()));
        await prefs.setString(
          'alera.mobile.codex.defaults',
          jsonEncode(preferences.toJson()),
        );
      }, preferences: _preferences);

  String _key(String hostId) => 'alera.mobile.codex.preferences.$hostId';
}
