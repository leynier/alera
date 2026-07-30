import 'package:alera/src/features/settings/presentation/settings_search_entries.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entries_terminal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orchestration skill is searchable in the agents skill group', () {
    final entry = agentsSearchEntries.singleWhere(
      (candidate) => candidate.title == 'Alera Orchestration Skill',
    );

    expect(entry.matches('orchestration'), isTrue);
    expect(entry.groupId, 'cliSkill');
  });

  test('computer use skill is searchable in the agents skill group', () {
    final entry = agentsSearchEntries.singleWhere(
      (candidate) => candidate.title == 'Alera Computer Use Skill',
    );

    expect(entry.matches('accessibility'), isTrue);
    expect(entry.groupId, 'cliSkill');
  });

  test('Grok Build hooks are searchable in the hooks group', () {
    final entry = agentsSearchEntries.singleWhere(
      (candidate) => candidate.title == 'Grok Build Hooks',
    );

    expect(entry.matches('grok'), isTrue);
    expect(entry.matches('xai'), isTrue);
    expect(entry.groupId, 'hooks');
  });

  test(
    'Kimi API key variable is searchable in the quota credentials group',
    () {
      final entry = quotaSearchEntries.singleWhere(
        (candidate) => candidate.title == 'Kimi API Key Variable',
      );

      expect(entry.matches('kimi_api_key'), isTrue);
      expect(entry.groupId, 'credentials');
    },
  );

  test('terminal TUI interaction settings are searchable', () {
    final entry = terminalSearchEntries.singleWhere(
      (candidate) => candidate.title == 'TUI Scroll Speed',
    );

    expect(entry.matches('opencode'), isTrue);
    expect(entry.matches('mouse wheel'), isTrue);
    expect(entry.groupId, 'interaction');
  });
}
