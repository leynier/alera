import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_view_prefs_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_text_search_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

const _result = MobileWorkspaceSearchResult(
  totalMatches: 3,
  files: <MobileWorkspaceSearchFile>[
    MobileWorkspaceSearchFile(
      relativePath: 'a.dart',
      contentToken: '10:1',
      matches: <MobileWorkspaceSearchMatch>[
        MobileWorkspaceSearchMatch(
          id: 'a.dart:1:1:0',
          line: 1,
          column: 1,
          matchLength: 3,
          lineContent: 'foo',
        ),
        MobileWorkspaceSearchMatch(
          id: 'a.dart:2:1:1',
          line: 2,
          column: 1,
          matchLength: 3,
          lineContent: 'foo',
        ),
      ],
    ),
    MobileWorkspaceSearchFile(
      relativePath: 'b.dart',
      contentToken: '20:2',
      matches: <MobileWorkspaceSearchMatch>[
        MobileWorkspaceSearchMatch(
          id: 'b.dart:1:1:0',
          line: 1,
          column: 1,
          matchLength: 3,
          lineContent: 'foo',
        ),
      ],
    ),
  ],
);

(ProviderContainer, FakeTerminalClient) _setUp() {
  final client = FakeTerminalClient()
    ..workspaceSearchSupported = true
    ..workspaceReplaceSupported = true
    ..searchResult = _result
    ..replaceResult = const MobileWorkspaceReplaceResult(
      filesChanged: 1,
      matchesReplaced: 1,
    );
  final container = ProviderContainer(
    overrides: [
      workspaceClientProvider('host-1').overrideWith((ref) async => client),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  return (container, client);
}

void main() {
  test('search sends the replacement and a cancellation id', () async {
    final (container, client) = _setUp();
    final provider = workspaceTextSearchControllerProvider('host-1', 'ws-1');
    final notifier = container.read(provider.notifier);

    notifier
      ..setQuery('foo')
      ..setReplacement('bar');
    await notifier.runNow();

    final request = client.searchRequests.last;
    expect(request['query'], 'foo');
    expect(request['replacement'], 'bar');
    expect(request['requestId'], isA<String>());
    expect(container.read(provider).result?.totalMatches, 3);
  });

  test('replace in file sends its ids and only its content token', () async {
    final (container, client) = _setUp();
    final provider = workspaceTextSearchControllerProvider('host-1', 'ws-1');
    final notifier = container.read(provider.notifier);
    notifier
      ..setQuery('foo')
      ..setReplacement('bar');
    await notifier.runNow();

    final replaced = await notifier.replaceMatches(<String>[
      'a.dart:1:1:0',
      'a.dart:2:1:1',
    ]);

    expect(replaced.matchesReplaced, 1);
    final request = client.replaceRequests.single;
    expect(request['replacement'], 'bar');
    expect(request['matchIds'], <String>['a.dart:1:1:0', 'a.dart:2:1:1']);
    expect(request['expectedFiles'], <String, String>{'a.dart': '10:1'});
  });

  test('replace all sends every file token and no ids', () async {
    final (container, client) = _setUp();
    final notifier = container.read(
      workspaceTextSearchControllerProvider('host-1', 'ws-1').notifier,
    );
    notifier.setQuery('foo');
    await notifier.runNow();

    await notifier.replaceMatches(const <String>[]);

    final request = client.replaceRequests.single;
    expect(request['matchIds'], isEmpty);
    expect(request['expectedFiles'], <String, String>{
      'a.dart': '10:1',
      'b.dart': '20:2',
    });
  });

  test('replace all is refused while results are truncated', () async {
    final (container, client) = _setUp();
    client.searchResult = const MobileWorkspaceSearchResult(
      totalMatches: 1,
      truncated: true,
      files: <MobileWorkspaceSearchFile>[
        MobileWorkspaceSearchFile(relativePath: 'a.dart'),
      ],
    );
    final provider = workspaceTextSearchControllerProvider('host-1', 'ws-1');
    final notifier = container.read(provider.notifier);
    notifier.setQuery('foo');
    await notifier.runNow();

    expect(container.read(provider).canReplaceAll, isFalse);
    await expectLater(
      notifier.replaceMatches(const <String>[]),
      throwsA(isA<StateError>()),
    );
    expect(client.replaceRequests, isEmpty);
  });

  test('replace is refused by a host without the capability', () async {
    final (container, client) = _setUp();
    client.workspaceReplaceSupported = false;
    final notifier = container.read(
      workspaceTextSearchControllerProvider('host-1', 'ws-1').notifier,
    );
    notifier.setQuery('foo');
    await notifier.runNow();

    await expectLater(
      notifier.replaceMatches(const <String>['a.dart:1:1:0']),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('collapse all toggles every file node and back', () async {
    final (container, _) = _setUp();
    final provider = workspaceTextSearchControllerProvider('host-1', 'ws-1');
    final notifier = container.read(provider.notifier);
    notifier.setQuery('foo');
    await notifier.runNow();

    notifier.toggleAllResultsCollapsed();
    expect(container.read(provider).allResultsCollapsed, isTrue);
    notifier.toggleAllResultsCollapsed();
    expect(container.read(provider).collapsedResultNodeKeys, isEmpty);
  });

  test('view options follow and write the shared view prefs', () async {
    final (container, client) = _setUp();
    client.viewPrefs = const MobileViewPrefs(
      searchViewAsTree: true,
      searchIncludeIgnored: true,
    );
    await container.read(mobileViewPrefsControllerProvider('host-1').future);
    final provider = workspaceTextSearchControllerProvider('host-1', 'ws-1');
    final notifier = container.read(provider.notifier);

    expect(container.read(provider).viewAsTree, isTrue);
    expect(container.read(provider).includeIgnored, isTrue);

    notifier.toggleViewAsTree();
    await pumpEventQueue();

    expect(container.read(provider).viewAsTree, isFalse);
    expect(client.viewPrefs.searchViewAsTree, isFalse);
    expect(client.viewPrefs.searchIncludeIgnored, isTrue);
  });

  test('clear keeps the toggles and drops the query and results', () async {
    final (container, _) = _setUp();
    final provider = workspaceTextSearchControllerProvider('host-1', 'ws-1');
    final notifier = container.read(provider.notifier);
    notifier
      ..toggleCaseSensitive()
      ..setQuery('foo');
    await notifier.runNow();

    notifier.clear();

    final state = container.read(provider);
    expect(state.query, isEmpty);
    expect(state.result, isNull);
    expect(state.caseSensitive, isTrue);
  });
}
