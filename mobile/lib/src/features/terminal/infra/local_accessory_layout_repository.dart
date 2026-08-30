import 'dart:convert';
import 'package:alera_mobile/src/features/configuration_sync/infra/mobile_configuration_preferences.dart';

import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/terminal/application/accessory_layout_repository.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalAccessoryLayoutRepository implements AccessoryLayoutRepository {
  LocalAccessoryLayoutRepository({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _key = 'alera.mobile.terminalAccessoryLayout';

  final SharedPreferencesAsync _preferences;

  @override
  Future<TerminalAccessoryLayout> load() =>
      MobileConfigurationPreferences.transaction((_) async {
        final encoded = await _preferences.getString(_key);
        if (encoded == null || encoded.trim().isEmpty) {
          return TerminalAccessoryLayout.defaults();
        }
        try {
          return TerminalAccessoryLayout.fromJson(
            asJsonMap(jsonDecode(encoded)),
          );
        } on FormatException {
          return TerminalAccessoryLayout.defaults();
        }
      }, preferences: _preferences);

  @override
  Future<void> save(TerminalAccessoryLayout layout) {
    return MobileConfigurationPreferences.transaction(
      (prefs) => prefs.setString(_key, jsonEncode(layout.toJson())),
      preferences: _preferences,
    );
  }
}
