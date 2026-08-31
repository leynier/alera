import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// All participating repositories share this lane, including recovery after a crash.
class MobileConfigurationPreferences {
  static Future<void> _tail = Future<void>.value();
  static const journalKey = 'alera.configuration.applyJournal';
  static Future<T> transaction<T>(
    Future<T> Function(SharedPreferencesAsync) action, {
    SharedPreferencesAsync? preferences,
  }) {
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        final prefs = preferences ?? SharedPreferencesAsync();
        await recover(prefs);
        result.complete(await action(prefs));
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  static Future<void> recover(SharedPreferencesAsync prefs) async {
    final raw = await prefs.getString(journalKey);
    if (raw == null) return;
    final writes = await compute(_decodeJournal, raw);
    for (final entry in writes.entries) {
      await prefs.setString(entry.key, entry.value);
    }
    await prefs.remove(journalKey);
  }

  static Future<void> apply(
    SharedPreferencesAsync prefs,
    Map<String, String> writes,
  ) async {
    await prefs.setString(journalKey, await compute(_encodeJournal, writes));
    await recover(prefs);
  }

  static Future<String?> dictation(SharedPreferencesAsync prefs) async {
    final existing = await prefs.getString('aiDictation.settings');
    if (existing != null) return existing;
    final legacy = await SharedPreferences.getInstance();
    final raw = legacy.getString('aiDictation.settings');
    if (raw != null) await prefs.setString('aiDictation.settings', raw);
    return raw;
  }
}

Map<String, String> _decodeJournal(String raw) =>
    Map<String, String>.from(jsonDecode(raw) as Map);
String _encodeJournal(Map<String, String> writes) => jsonEncode(writes);
