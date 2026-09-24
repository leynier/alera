import 'dart:convert';

import 'package:alera_mobile/src/features/workbench/application/explorer_preferences_repository.dart';
import 'package:alera_mobile/src/features/workbench/domain/explorer_preferences.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

final Logger _logger = Logger('LocalExplorerPreferencesRepository');

class LocalExplorerPreferencesRepository({SharedPreferencesAsync? preferences})
    implements ExplorerPreferencesRepository {
  this : _injected = preferences;

  static const String _keyPrefix = 'alera.mobile.explorerPrefs.';

  final SharedPreferencesAsync? _injected;

  // Created on first use, inside the error handling below: the constructor
  // throws when no platform implementation is registered.
  SharedPreferencesAsync get _preferences =>
      _injected ?? SharedPreferencesAsync();

  @override
  Future<ExplorerPreferences> load(String hostId, String workspaceId) async {
    try {
      final encoded = await _preferences.getString(_key(hostId, workspaceId));
      if (encoded == null || encoded.isEmpty) {
        return const ExplorerPreferences();
      }
      final decoded = jsonDecode(encoded);
      return decoded is Map
          ? ExplorerPreferences.fromJson(Map<String, Object?>.from(decoded))
          : const ExplorerPreferences();
    } on Object catch (error, stackTrace) {
      // A view preference must never stop the explorer from opening.
      _logger.warning('could not read explorer preferences', error, stackTrace);
      return const ExplorerPreferences();
    }
  }

  @override
  Future<void> save(
    String hostId,
    String workspaceId,
    ExplorerPreferences preferences,
  ) async {
    try {
      await _preferences.setString(
        _key(hostId, workspaceId),
        jsonEncode(preferences.toJson()),
      );
    } on Object catch (error, stackTrace) {
      _logger.warning('could not save explorer preferences', error, stackTrace);
    }
  }

  String _key(String hostId, String workspaceId) =>
      '$_keyPrefix$hostId.$workspaceId';
}
