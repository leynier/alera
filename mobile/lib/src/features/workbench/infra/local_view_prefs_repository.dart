import 'dart:convert';

import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/workbench/application/view_prefs_repository.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalViewPrefsRepository implements ViewPrefsRepository {
  LocalViewPrefsRepository({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _keyPrefix = 'alera.mobile.viewPrefs.';

  final SharedPreferencesAsync _preferences;

  @override
  Future<MobileViewPrefs> load(String hostId) async {
    final encoded = await _preferences.getString('$_keyPrefix$hostId');
    if (encoded == null || encoded.trim().isEmpty) {
      return const MobileViewPrefs();
    }
    try {
      return MobileViewPrefs.fromJson(asJsonMap(jsonDecode(encoded)));
    } on FormatException {
      return const MobileViewPrefs();
    }
  }

  @override
  Future<void> save(String hostId, MobileViewPrefs prefs) {
    return _preferences.setString(
      '$_keyPrefix$hostId',
      jsonEncode(prefs.toJson()),
    );
  }
}
