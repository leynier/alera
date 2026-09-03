import 'dart:convert';

import 'package:alera/src/features/settings/presentation/ai_dictation_search_entries.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entries.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entries_quota.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entries_terminal.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';
import 'package:alera/src/features/settings/presentation/text_actions_search_entries.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _SearchCase = ({
  List<SettingsSearchEntry> entries,
  String query,
  List<(String, String?)> expected,
});

void main() {
  test('search catalogs preserve exact metadata and order', () {
    final catalogs = <String, List<SettingsSearchEntry>>{
      'application': applicationSearchEntries,
      'agents': agentsSearchEntries,
      'keyboard': keyboardSearchEntries,
      'browser': browserSearchEntries,
      'editor': editorSearchEntries,
      'aiAssist': aiAssistSearchEntries,
      'aiDictation': aiDictationSearchEntries,
      'textActions': textActionsSearchEntries,
      'quota': quotaSearchEntries,
    };

    expect(
      _catalogFingerprint(catalogs),
      '3f5bcd1ea73ed8210cdd50a9f4de90b15f1b9a019a9d6842d3637a20631edc22',
    );
  });

  test('built search catalogs remain immutable', () {
    expect(
      () => textActionsSearchEntries.add(
        const SettingsSearchEntry(title: 'Unexpected Entry'),
      ),
      throwsUnsupportedError,
    );
  });

  test('search results retain their section order and navigation groups', () {
    final cases = <_SearchCase>[
      (
        entries: aiAssistSearchEntries,
        query: 'regenerate',
        expected: <(String, String?)>[('AI Assist Agent Titles', 'agentTitle')],
      ),
      (
        entries: applicationSearchEntries,
        query: 'sidecar',
        expected: <(String, String?)>[
          ('Keep Runtime Open When App Quits', 'runtime'),
          ('Empty Host Shutdown', 'runtime'),
          ('Detached Session Shutdown', 'runtime'),
        ],
      ),
      (
        entries: applicationSearchEntries,
        query: 'keep-alive',
        expected: <(String, String?)>[('Keep Computer Awake', 'runtime')],
      ),
      (
        entries: applicationSearchEntries,
        query: 'tray',
        expected: <(String, String?)>[
          ('Show Tray Icon', 'desktop'),
          ('Show Tray Badge', 'desktop'),
        ],
      ),
      (
        entries: applicationSearchEntries,
        query: 'number',
        expected: <(String, String?)>[('Show Tray Badge', 'desktop')],
      ),
      (
        entries: applicationSearchEntries,
        query: 'taskbar',
        expected: <(String, String?)>[('Show Dock Badge', 'desktop')],
      ),
      (
        entries: applicationSearchEntries,
        query: 'pull request',
        expected: <(String, String?)>[
          ('Show Pull Request Status', 'pullRequests'),
          ('Notify When Checks Fail', 'pullRequests'),
        ],
      ),
      (
        entries: agentsSearchEntries,
        query: 'xai',
        expected: <(String, String?)>[('Grok Build Hooks', 'hooks')],
      ),
      (
        entries: agentsSearchEntries,
        query: 'sidebar',
        expected: <(String, String?)>[
          ('Show Tab Titles in Sidebar', 'behavior'),
        ],
      ),
      (
        entries: browserSearchEntries,
        query: 'self signed',
        expected: <(String, String?)>[
          ('Trusted Local Certificates', 'certificates'),
        ],
      ),
      (
        entries: aiDictationSearchEntries,
        query: 'privacy',
        expected: <(String, String?)>[('Whisper Model', 'models')],
      ),
      (
        entries: textActionsSearchEntries,
        query: 'destructive',
        expected: <(String, String?)>[('Delete', 'actions')],
      ),
      (
        entries: quotaSearchEntries,
        query: 'visible',
        expected: <(String, String?)>[('Claude Default in Usage', 'claude')],
      ),
    ];

    for (final testCase in cases) {
      expect(
        testCase.entries
            .where((entry) => entry.matches(testCase.query))
            .map((entry) => (entry.title, entry.groupId)),
        testCase.expected,
        reason: testCase.query,
      );
    }
  });

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

  test('Agent Canvas skill is searchable in the agents skill group', () {
    final entry = agentsSearchEntries.singleWhere(
      (candidate) => candidate.title == 'Agent Canvas Skill',
    );

    expect(entry.matches('canvas'), isTrue);
    expect(entry.matches('decision'), isTrue);
    expect(entry.groupId, 'cliSkill');
  });

  test('Agent Profiles skill is searchable in the extra skills group', () {
    final entry = agentsSearchEntries.singleWhere(
      (candidate) => candidate.title == 'Agent Profiles Skill',
    );

    expect(entry.matches('quota'), isTrue);
    expect(entry.matches('managed'), isTrue);
    expect(entry.groupId, 'extraSkills');
  });

  test('sidebar tab titles are searchable in the agents behavior group', () {
    final entry = agentsSearchEntries.singleWhere(
      (candidate) => candidate.title == 'Show Tab Titles in Sidebar',
    );

    expect(entry.matches('sidebar'), isTrue);
    expect(entry.matches('regenerate'), isTrue);
    expect(entry.groupId, 'behavior');
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

  test('terminal toolbar corner is searchable in appearance', () {
    final entry = terminalSearchEntries.singleWhere(
      (candidate) => candidate.title == 'Toolbar Corner',
    );

    expect(entry.matches('overlay'), isTrue);
    expect(entry.matches('move'), isTrue);
    expect(entry.groupId, 'appearance');
  });
}

String _catalogFingerprint(Map<String, List<SettingsSearchEntry>> catalogs) {
  final data = <String, Object?>{
    for (final catalog in catalogs.entries)
      catalog.key: <Map<String, Object?>>[
        for (final entry in catalog.value)
          <String, Object?>{
            'title': entry.title,
            'description': entry.description,
            'keywords': entry.keywords,
            'groupId': entry.groupId,
          },
      ],
  };
  final snapshot = '${const JsonEncoder.withIndent('  ').convert(data)}\n';
  return sha256.convert(utf8.encode(snapshot)).toString();
}
