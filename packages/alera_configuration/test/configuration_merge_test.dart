import 'package:alera_configuration/alera_configuration.dart';
import 'package:test/test.dart';

ConfigurationDocument doc(JsonMap desktop, {JsonMap? mobile}) =>
    ConfigurationDocument.empty().withBlocks({
      'desktop': desktop,
      if (mobile != null) 'mobile': mobile,
    });
void main() {
  test('profiles use stable ids, expose ordering and reject duplicate names or missing defaults', () {
    ConfigurationDocument profiles(List<JsonMap> items) =>
        ConfigurationDocument.empty().withBlocks({
          'shared': {'agentProfiles': portableCatalog(items)},
        });
    const one = {'id': 'a', 'name': 'One', 'command': 'agent'};
    const two = {'id': 'b', 'name': 'Two', 'command': 'agent'};
    final merge = ConfigurationMerge(
      base: profiles([one, two]),
      local: profiles([
        two,
        {...one, 'command': 'agent --local'},
      ]),
      remote: profiles([
        {...one, 'name': 'Renamed'},
        two,
      ]),
    );
    final result = merge.resolve();
    final items = catalogItems(jsonMap(result.json['shared'])['agentProfiles']);
    expect(items.map((p) => p['id']), ['b', 'a']);
    expect(items.last['name'], 'Renamed');
    expect(items.last['command'], 'agent --local');
    expect(
      validateConfiguration(
        profiles([
          one,
          {...two, 'name': 'one'},
        ]),
      ),
      isNotEmpty,
    );
    final missing = result.withBlocks({
      'desktop': {
        'settings': {
          'agents': {'defaultAgentProfileId': 'missing'},
        },
      },
    });
    expect(validateConfiguration(missing), isNotEmpty);
    expect(validateConfiguration(missing, ownedBlocks: {'mobile'}), isEmpty);
  });
  test('independent edits survive and conflicts require a decision', () {
    final merge = ConfigurationMerge(
      base: doc({'font': 12, 'theme': 'dark'}),
      local: doc({'font': 14, 'theme': 'dark'}),
      remote: doc({'font': 12, 'theme': 'blue'}),
    );
    expect(merge.resolve().json['desktop'], {'font': 14, 'theme': 'blue'});
    final conflict = ConfigurationMerge(
      base: doc({'font': 12}),
      local: doc({'font': 14}),
      remote: doc({'font': 16}),
    );
    expect(conflict.hasUnresolved, isTrue);
    expect(conflict.resolve, throwsStateError);
    conflict.chooseAll(ConfigurationChoice.remote);
    expect(conflict.resolve().json['desktop'], {'font': 16});
  });
  test(
    'first connection preserves additions and distinguishes null from absence',
    () {
      final merge = ConfigurationMerge(
        local: doc({'a': null}),
        remote: doc({'b': 3}),
      );
      expect(merge.resolve().json['desktop'], {'a': null, 'b': 3});
      final conflict = ConfigurationMerge(
        local: doc({'a': null}),
        remote: doc({'a': 3}),
      );
      expect(conflict.hasUnresolved, isTrue);
    },
  );
  test(
    'deletion conflicts with editing an entity and can be resolved either way',
    () {
      final base = doc({
        'profiles': {
          'id': {'name': 'Old'},
        },
      });
      final local = doc({'profiles': <String, Object?>{}});
      final remote = doc({
        'profiles': {
          'id': {'name': 'New'},
        },
      });
      final merge = ConfigurationMerge(
        base: base,
        local: local,
        remote: remote,
      );
      expect(merge.hasUnresolved, isTrue);
      merge.chooseAll(ConfigurationChoice.local);
      expect(merge.resolve().json['desktop'], {'profiles': {}});
      merge.chooseAll(ConfigurationChoice.remote);
      expect(merge.resolve().json['desktop'], {
        'profiles': {
          'id': {'name': 'New'},
        },
      });
    },
  );
  test('mobile upload preserves desktop and unknown future blocks', () {
    final remote = ConfigurationDocument({
      ...doc({'font': 15}).json,
      'future': {'x': 3},
    });
    final merge = ConfigurationMerge(
      local: doc(
        {},
        mobile: {
          'keys': ['Esc'],
        },
      ),
      remote: remote,
      ownedBlocks: {'mobile'},
    );
    final result = merge.resolve().json;
    expect(result['desktop'], {'font': 15});
    expect(result['future'], {'x': 3});
    expect(result['mobile'], {
      'keys': ['Esc'],
    });
  });
  test(
    'portable settings cannot export paths, hooks, credentials or caches',
    () {
      final result = portableDesktopSettings({
        'general': {'workspaceDirectory': '/secret', 'showTrayIcon': true},
        'agents': {
          'agentStatusHooks': {'codex': true},
          'quotas': {'token': 'secret'},
        },
        'aiDictation': {
          'remoteConsentVersion': 2,
          'localModelId': 'downloaded',
          'language': 'es',
        },
        'aiTextGeneration': {
          'discoveredModelsByAgent': {
            'codex': ['x'],
          },
        },
      });
      expect(result['general'], {'showTrayIcon': true});
      expect(result['agents'], isEmpty);
      expect(result['aiDictation'], {'language': 'es'});
      expect(result['aiTextGeneration'], isEmpty);
    },
  );
  test('future formats and oversized documents are rejected', () {
    expect(
      () => ConfigurationDocument({...doc({}).json, 'schemaVersion': 2}),
      throwsFormatException,
    );
    expect(
      () => doc({'prompt': 'a' * configurationMaxBytes}),
      throwsFormatException,
    );
  });
  test('simultaneous text action additions can be renamed before applying', () {
    ConfigurationDocument action(String id) =>
        ConfigurationDocument.empty().withBlocks({
          'shared': {
            'textActions': portableCatalog([
              {'id': id, 'name': 'Summarize', 'prompt': 'Summarize this'},
            ]),
          },
        });
    final merge = ConfigurationMerge(
      base: ConfigurationDocument.empty(),
      local: action('local'),
      remote: action('remote'),
    );
    merge.chooseAll(ConfigurationChoice.remote);
    final localAddition = merge.differences.firstWhere(
      (d) => d.path.last == 'local',
    );
    localAddition.choice = ConfigurationChoice.local;
    expect(validateConfiguration(merge.resolve()), isNotEmpty);
    expect(localAddition.canRename, isTrue);
    localAddition.rename('Summarize Locally');
    expect(validateConfiguration(merge.resolve()), isEmpty);
  });
}
