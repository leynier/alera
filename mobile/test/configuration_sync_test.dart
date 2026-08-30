import 'package:alera_mobile/src/features/codex_chat/infra/local_mobile_codex_preferences_repository.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_preferences.dart';
import 'dart:convert';
import 'package:alera_configuration/alera_configuration.dart';
import 'package:alera_mobile/src/features/configuration_sync/infra/mobile_configuration_preferences.dart';
import 'package:alera_mobile/src/features/configuration_sync/infra/mobile_configuration_target.dart';
import 'package:alera_mobile/src/features/terminal/infra/local_accessory_layout_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
  });
  MobileConfigurationTarget target(String account) => MobileConfigurationTarget(
    accountId: account,
    onApplied: () {},
    ensureAccount: () async {},
  );

  test(
    'near-limit snapshots keep stable fingerprints through apply and publication',
    () async {
      final prefs = SharedPreferencesAsync();
      final phone = target('one');
      final before = await phone.read();
      final document = before.document.withBlocks({
        'desktop': {'futurePrompt': 'x' * (480 * 1024)},
      });
      final base = ConfigurationRevision(revision: 1, document: document);
      final pending = <String, Object?>{
        'operationId': 'large-upload',
        'document': document.json,
      };
      await phone.apply(
        document: document,
        expectedFingerprint: before.fingerprint,
        base: base,
        pending: pending,
      );
      final applied = await phone.read();
      final state = jsonDecode(
        (await prefs.getString('alera.configuration.state.one'))!,
      );
      expect(
        applied.fingerprint,
        configurationDigest({
          'document': applied.document.json,
          'state': state,
        }),
      );
      expect(applied.pending, pending);
      expect(applied.base!.document.json, document.json);
      expect((await phone.read()).fingerprint, applied.fingerprint);
      await phone.published(
        'large-upload',
        ConfigurationRevision(revision: 2, document: document),
      );
      final published = await phone.read();
      expect(published.base!.revision, 2);
      expect(published.pending, isNull);
      expect(published.document.json, applied.document.json);
      expect(
        await prefs.getString(MobileConfigurationPreferences.journalKey),
        isNull,
      );
    },
  );

  test(
    'phone import preserves consent, credentials and foreign blocks',
    () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString(
        'aiDictation.settings',
        jsonEncode({
          'language': 'en',
          'remoteAudioConsentVersion': 2,
          'localModelId': 'whisper-large',
        }),
      );
      await prefs.setString('unrelatedCredential', 'local-only');
      final phone = target('one');
      final before = await phone.read();
      final mobile = {
        ...jsonMap(before.document.json['mobile']),
        'dictation': {'language': 'es', 'remoteAudioConsentVersion': 99},
      };
      final document = before.document.withBlocks({
        'mobile': mobile,
        'desktop': {'future': true},
      });
      await phone.apply(
        document: document,
        expectedFingerprint: before.fingerprint,
        base: null,
        pending: {'operationId': 'one'},
      );
      final saved = jsonMap(
        jsonDecode((await prefs.getString('aiDictation.settings'))!),
      );
      expect(saved['language'], 'es');
      expect(saved['remoteAudioConsentVersion'], 2);
      expect(saved['localModelId'], 'whisper-large');
      expect(await prefs.getString('unrelatedCredential'), 'local-only');
      expect((await phone.read()).document.json['desktop'], {'future': true});
      expect((await target('two').read()).pending, isNull);
      await expectLater(
        phone.apply(
          document: document,
          expectedFingerprint: before.fingerprint,
          base: null,
          pending: null,
        ),
        throwsStateError,
      );
    },
  );
  test(
    'a pending journal recovers before a normal preferences reader sees data',
    () async {
      final prefs = SharedPreferencesAsync();
      final desired = {
        'orderedIds': ['escape'],
        'hiddenIds': ['tab'],
        'customKeys': [],
      };
      await prefs.setString(
        MobileConfigurationPreferences.journalKey,
        jsonEncode({
          MobileConfigurationTarget.accessoryKey: jsonEncode(desired),
          'recoveryMarker': 'done',
        }),
      );
      await LocalAccessoryLayoutRepository().load();
      expect(await prefs.getString('recoveryMarker'), 'done');
      expect(
        await prefs.getString(MobileConfigurationPreferences.journalKey),
        isNull,
      );
      expect(
        jsonDecode(
          (await prefs.getString(MobileConfigurationTarget.accessoryKey))!,
        ),
        desired,
      );
    },
  );
  test('signing out prevents phone configuration application', () async {
    final phone = MobileConfigurationTarget(
      accountId: 'one',
      onApplied: () {},
      ensureAccount: () async => throw StateError('Signed out'),
    );
    await expectLater(phone.read(), throwsStateError);
  });
  test(
    'unsupported phone settings fail before writing instead of becoming defaults',
    () async {
      final phone = target('one');
      final before = await phone.read();
      final mobile = jsonMap(before.document.json['mobile']);
      mobile['dictation'] = {
        ...jsonMap(mobile['dictation']),
        'engine': 'futureEngine',
      };
      await expectLater(
        phone.apply(
          document: before.document.withBlocks({'mobile': mobile}),
          expectedFingerprint: before.fingerprint,
          base: null,
          pending: null,
        ),
        throwsFormatException,
      );
      expect((await phone.read()).fingerprint, before.fingerprint);
      expect(
        await SharedPreferencesAsync().getString(
          MobileConfigurationPreferences.journalKey,
        ),
        isNull,
      );
    },
  );
  test(
    'ordinary phone edits preserve opaque sync fields and custom key metadata',
    () async {
      final phone = target('one');
      final before = await phone.read();
      final mobile = jsonMap(before.document.json['mobile']);
      mobile['codex'] = {...jsonMap(mobile['codex']), 'futureMode': 'keep'};
      mobile['quickKeys'] = {
        ...jsonMap(mobile['quickKeys']),
        'futureLayout': true,
        'customKeys': [
          {
            'id': 'custom_one',
            'key': 'x',
            'modifiers': <String>[],
            'futureKey': 42,
          },
        ],
        'orderedIds': ['escape', 'future_builtin', 'custom_one'],
        'hiddenIds': ['future_builtin'],
      };
      await phone.apply(
        document: before.document.withBlocks({'mobile': mobile}),
        expectedFingerprint: before.fingerprint,
        base: null,
        pending: null,
      );
      await LocalMobileCodexPreferencesRepository().save(
        'host',
        const MobileCodexPreferences(planMode: true),
      );
      final keys = LocalAccessoryLayoutRepository();
      final current = await keys.load();
      await keys.save(
        current.copyWith(hiddenIds: {...current.hiddenIds, 'tab'}),
      );
      final saved = jsonMap((await phone.read()).document.json['mobile']);
      expect(jsonMap(saved['codex'])['futureMode'], 'keep');
      expect(jsonMap(saved['codex'])['planMode'], true);
      final layout = jsonMap(saved['quickKeys']);
      expect(layout['futureLayout'], true);
      expect(jsonMap((layout['customKeys'] as List).single)['futureKey'], 42);
      expect(layout['orderedIds'], contains('future_builtin'));
      expect(layout['hiddenIds'], containsAll(['future_builtin', 'tab']));
      await keys.save(current.copyWith(customKeys: [], orderedIds: ['escape']));
      expect(
        jsonMap((await phone.read()).document.json['mobile'])['quickKeys'],
        isNotNull,
      );
      expect(
        jsonMap(
          jsonMap((await phone.read()).document.json['mobile'])['quickKeys'],
        )['customKeys'],
        isEmpty,
      );
    },
  );
}
