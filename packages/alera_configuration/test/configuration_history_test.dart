import 'package:alera_configuration/alera_configuration.dart';
import 'package:alera_configuration/src/configuration_history.dart';
import 'package:test/test.dart';

void main() {
  test('restoring a profile catalog restores showInNewTabMenu without dropping newer fields', () {
    const profileId = 'prof_1';
    JsonMap profile({required bool showInNewTabMenu, String? futureField}) => {
      'id': profileId,
      'name': 'Codex',
      'agentType': 'codex',
      'command': 'codex',
      'showInNewTabMenu': showInNewTabMenu,
      if (futureField != null) 'futureField': futureField,
    };
    final current = ConfigurationDocument.empty().withBlocks({
      'shared': {
        'agentProfiles': portableCatalog([
          profile(showInNewTabMenu: true, futureField: 'keep'),
        ]),
      },
    });
    final historical = ConfigurationDocument.empty().withBlocks({
      'shared': {
        'agentProfiles': portableCatalog([profile(showInNewTabMenu: false)]),
      },
    });

    final restored = configurationForRestore(current, historical, {'shared'});
    final items = catalogItems(
      jsonMap(restored.json['shared'])['agentProfiles'],
    );
    expect(items.single['showInNewTabMenu'], isFalse);
    expect(items.single['futureField'], 'keep');
  });

  test('restoring a revision that omitted showInNewTabMenu does not keep the current opt-in', () {
    const profileId = 'prof_1';
    final current = ConfigurationDocument.empty().withBlocks({
      'shared': {
        'agentProfiles': portableCatalog([
          {
            'id': profileId,
            'name': 'Codex',
            'agentType': 'codex',
            'command': 'codex',
            'showInNewTabMenu': true,
          },
        ]),
      },
    });
    final historical = ConfigurationDocument.empty().withBlocks({
      'shared': {
        'agentProfiles': portableCatalog([
          {
            'id': profileId,
            'name': 'Codex',
            'agentType': 'codex',
            'command': 'codex',
          },
        ]),
      },
    });

    final restored = configurationForRestore(current, historical, {'shared'});
    final items = catalogItems(
      jsonMap(restored.json['shared'])['agentProfiles'],
    );
    expect(items.single['showInNewTabMenu'], isNot(true));
  });
}
