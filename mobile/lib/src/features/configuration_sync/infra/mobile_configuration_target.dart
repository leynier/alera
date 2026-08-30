import 'package:alera_configuration/alera_configuration.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mobile_configuration_codec.dart';
import 'mobile_configuration_preferences.dart';

class MobileConfigurationTarget implements ConfigurationLocalTarget {
  MobileConfigurationTarget({
    required this.accountId,
    required this.onApplied,
    required this.ensureAccount,
    this.label = 'This Phone',
  });
  final String accountId;
  final void Function() onApplied;
  final Future<void> Function() ensureAccount;
  @override
  final String label;
  @override
  Set<String> get ownedBlocks => const {'mobile'};
  String get _stateKey => 'alera.configuration.state.$accountId';
  static const accessoryKey = mobileConfigurationAccessoryKey;
  static const codexKey = mobileConfigurationCodexKey;

  @override
  Future<ConfigurationLocalSnapshot> read() async {
    await ensureAccount();
    return MobileConfigurationPreferences.transaction(_read);
  }

  Future<ConfigurationLocalSnapshot> _read(SharedPreferencesAsync prefs) async {
    // Capture under the preferences lane; decoding and hashing may span three documents.
    final raw = <String, String?>{
      'state': await prefs.getString(_stateKey),
      'document': await prefs.getString(mobileConfigurationDocumentKey),
      'dictation': await MobileConfigurationPreferences.dictation(prefs),
      'accessory': await prefs.getString(accessoryKey),
      'codex': await prefs.getString(codexKey),
    };
    return compute(
      decodeMobileConfigurationSnapshot,
      raw,
      debugLabel: 'configuration-snapshot',
    );
  }

  @override
  Future<void> apply({
    required ConfigurationDocument document,
    required String expectedFingerprint,
    required ConfigurationRevision? base,
    required JsonMap? pending,
  }) async {
    await ensureAccount();
    await MobileConfigurationPreferences.transaction((prefs) async {
      final before = await _read(prefs);
      if (before.fingerprint != expectedFingerprint) {
        throw StateError('Phone configuration changed. Review it again.');
      }
      final writes = await compute(
        encodeMobileConfigurationApplication,
        (
          document: document,
          before: before.document,
          base: base,
          pending: pending,
          stateKey: _stateKey,
          backupKey: 'alera.configuration.backup.$accountId',
          dictationRaw: await MobileConfigurationPreferences.dictation(prefs),
          // Host ids stay local and never enter the portable document.
          hostPreferenceKeys: (await prefs.getKeys())
              .where((key) => key.startsWith('alera.mobile.codex.preferences.'))
              .toList(),
        ),
        debugLabel: 'configuration-application',
      );
      await ensureAccount();
      await MobileConfigurationPreferences.apply(prefs, writes);
    });
    onApplied();
  }

  @override
  Future<void> published(
    String operationId,
    ConfigurationRevision revision,
  ) async {
    await ensureAccount();
    await MobileConfigurationPreferences.transaction((prefs) async {
      final encoded = await compute(
        encodeMobileConfigurationPublication,
        (
          state: await prefs.getString(_stateKey),
          operationId: operationId,
          revision: revision,
        ),
        debugLabel: 'configuration-publication',
      );
      await ensureAccount();
      await prefs.setString(_stateKey, encoded);
    });
  }
}
