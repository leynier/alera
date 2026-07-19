import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalWorkspaceAgentExpansionRepository {
  LocalWorkspaceAgentExpansionRepository({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const String _keyPrefix = 'alera.mobile.workspaceAgentExpansion.';

  final SharedPreferencesAsync _preferences;

  Future<Set<String>> load(String hostId) async {
    final encoded = await _preferences.getString('$_keyPrefix$hostId');
    if (encoded == null || encoded.isEmpty) {
      return const <String>{};
    }
    try {
      final decoded = jsonDecode(encoded);
      return decoded is List
          ? decoded.whereType<String>().toSet()
          : const <String>{};
    } on FormatException {
      return const <String>{};
    }
  }

  Future<void> save(String hostId, Set<String> workspaceIds) {
    final sorted = workspaceIds.toList()..sort();
    return _preferences.setString('$_keyPrefix$hostId', jsonEncode(sorted));
  }
}
