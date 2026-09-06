import 'dart:convert';

import 'package:alera_configuration/alera_configuration.dart';
import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_layout.dart';

import 'mobile_configuration_quick_keys.dart';

const mobileConfigurationDocumentKey = 'alera.configuration.mobile.document';
const mobileConfigurationAccessoryKey = 'alera.mobile.terminalAccessoryLayout';
const mobileConfigurationCodexKey = 'alera.mobile.codex.defaults';

ConfigurationLocalSnapshot decodeMobileConfigurationSnapshot(
  Map<String, String?> raw,
) {
  final state = _decode(raw['state']);
  final stored = _decode(raw['document']);
  final document = stored.isEmpty
      ? ConfigurationDocument.empty()
      : ConfigurationDocument(stored);
  final dictation = MobileAiDictationSettings.fromJson(
    _decode(raw['dictation']),
  );
  final accessory = _decode(raw['accessory']);
  final codex = _decode(raw['codex']);
  final retained = jsonMap(document.json['mobile']);
  final mobile = {
    ...retained,
    'quickKeys': preserveQuickKeys(
      jsonMap(retained['quickKeys']),
      accessory.isEmpty
          ? TerminalAccessoryLayout.defaults().toJson()
          : accessory,
    ),
    'codex': {...jsonMap(retained['codex']), ...jsonMap(codex)},
    'dictation': {
      ...jsonMap(retained['dictation']),
      ...pickFields(dictation.toJson(), mobileDictationFields),
    },
  };
  final next = document.withBlocks({'mobile': mobile});
  return ConfigurationLocalSnapshot(
    document: next,
    fingerprint: configurationDigest({'document': next.json, 'state': state}),
    base: state['base'] == null
        ? null
        : ConfigurationRevision.fromJson(jsonMap(state['base'])),
    pending: state['pending'] == null ? null : jsonMap(state['pending']),
  );
}

typedef MobileConfigurationApplication = ({
  ConfigurationDocument document,
  ConfigurationDocument before,
  ConfigurationRevision? base,
  JsonMap? pending,
  String stateKey,
  String backupKey,
  String? dictationRaw,
  List<String> hostPreferenceKeys,
});

Map<String, String> encodeMobileConfigurationApplication(
  MobileConfigurationApplication input,
) {
  final mobile = jsonMap(input.document.json['mobile']);
  final oldDictation = _decode(input.dictationRaw);
  final dictation = MobileAiDictationSettings.fromJson({
    ...(oldDictation
      ..removeWhere((key, _) => mobileDictationFields.contains(key))),
    ...pickFields(jsonMap(mobile['dictation']), mobileDictationFields),
  });
  final keys = TerminalAccessoryLayout.fromJson(jsonMap(mobile['quickKeys']));
  _requireSupportedValues(
    pickFields(jsonMap(mobile['dictation']), mobileDictationFields),
    dictation.toJson(),
  );
  final keyVersion = jsonMap(mobile['quickKeys'])['version'];
  if (keyVersion != null && keyVersion != terminalAccessoryLayoutVersion) {
    throw const FormatException(
      'Update Alera to import this quick key format.',
    );
  }
  return {
    mobileConfigurationDocumentKey: jsonEncode(input.document.json),
    input.stateKey: jsonEncode({
      'base': input.base?.toJson(),
      'pending': input.pending,
    }),
    input.backupKey: jsonEncode(input.before.json),
    mobileConfigurationAccessoryKey: jsonEncode({
      ...keys.toJson(),
      ...jsonMap(mobile['quickKeys']),
    }),
    mobileConfigurationCodexKey: jsonEncode(jsonMap(mobile['codex'])),
    'aiDictation.settings': jsonEncode(dictation.toJson()),
    for (final key in input.hostPreferenceKeys)
      key: jsonEncode(jsonMap(mobile['codex'])),
  };
}

String encodeMobileConfigurationPublication(
  ({String? state, String operationId, ConfigurationRevision revision}) input,
) {
  final state = _decode(input.state);
  if (jsonMap(state['pending'])['operationId'] != input.operationId) {
    throw StateError('Pending upload changed. Review again.');
  }
  return jsonEncode({'base': input.revision.toJson(), 'pending': null});
}

JsonMap _decode(String? raw) => raw == null ? {} : jsonMap(jsonDecode(raw));

void _requireSupportedValues(JsonMap imported, JsonMap parsed) {
  for (final entry in imported.entries) {
    if (!sameJson(entry.value, parsed[entry.key])) {
      throw FormatException(
        'Unsupported phone setting: ${entry.key}. Update Alera before importing.',
      );
    }
  }
}
