import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workspace_search_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_search_service.dart';
import 'package:alera/src/rust/api/workspace_search.dart' as native;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('whitespace-only query counts as searchable', () async {
    final service = _FakeWorkspaceSearchService();
    final container = ProviderContainer(
      overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final provider = workspaceSearchControllerProvider('workspace-1');
    final controller = container.read(provider.notifier);

    controller.setQuery('/workspace', ' ');

    final state = container.read(provider);
    expect(state.hasQuery, isTrue);
    expect(state.loading, isTrue);
  });

  test('search input changes clear stale results immediately', () async {
    final service = _FakeWorkspaceSearchService();
    final container = ProviderContainer(
      overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final provider = workspaceSearchControllerProvider('workspace-1');
    final controller = container.read(provider.notifier);
    controller.setQuery('/workspace', 'needle');
    await controller.searchNow('/workspace');
    expect(container.read(provider).result, isNotNull);

    controller.setIncludePattern('/workspace', 'lib/**');

    final state = container.read(provider);
    expect(state.result, isNull);
    expect(state.loading, isTrue);
    expect(state.error, isNull);
  });

  test('toggle all files collapsed collapses every result file', () async {
    final service = _FakeWorkspaceSearchService(result: _multiFileSearchResult);
    final container = ProviderContainer(
      overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final provider = workspaceSearchControllerProvider('workspace-1');
    final controller = container.read(provider.notifier);
    controller.setQuery('/workspace', 'needle');
    await controller.searchNow('/workspace');

    controller.toggleAllFilesCollapsed();

    expect(container.read(provider).collapsedResultNodeKeys, <String>{
      workspaceSearchFileNodeKey('lib/main.dart'),
      workspaceSearchFileNodeKey('lib/other.dart'),
    });
  });

  test(
    'toggle all files collapsed expands when every file is collapsed',
    () async {
      final service = _FakeWorkspaceSearchService(
        result: _multiFileSearchResult,
      );
      final container = ProviderContainer(
        overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final provider = workspaceSearchControllerProvider('workspace-1');
      final controller = container.read(provider.notifier);
      controller.setQuery('/workspace', 'needle');
      await controller.searchNow('/workspace');

      controller.toggleAllFilesCollapsed();
      controller.toggleAllFilesCollapsed();

      expect(container.read(provider).collapsedResultNodeKeys, isEmpty);
    },
  );

  test(
    'toggle all results collapsed collapses tree directories and files',
    () async {
      final service = _FakeWorkspaceSearchService(result: _treeSearchResult);
      final container = ProviderContainer(
        overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final provider = workspaceSearchControllerProvider('workspace-1');
      final controller = container.read(provider.notifier);
      controller.setQuery('/workspace', 'needle');
      await controller.searchNow('/workspace');
      controller.toggleViewAsTree();

      controller.toggleAllResultsCollapsed();

      expect(container.read(provider).collapsedResultNodeKeys, <String>{
        workspaceSearchDirectoryNodeKey('src'),
        workspaceSearchDirectoryNodeKey('src/components'),
        workspaceSearchDirectoryNodeKey('src/components/home'),
        workspaceSearchFileNodeKey('src/components/home/button.astro'),
        workspaceSearchFileNodeKey('src/components/home/card.astro'),
        workspaceSearchFileNodeKey('bun.lock'),
      });
    },
  );

  test(
    'toggle all results collapsed expands tree when every node is collapsed',
    () async {
      final service = _FakeWorkspaceSearchService(result: _treeSearchResult);
      final container = ProviderContainer(
        overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final provider = workspaceSearchControllerProvider('workspace-1');
      final controller = container.read(provider.notifier);
      controller.setQuery('/workspace', 'needle');
      await controller.searchNow('/workspace');
      controller.toggleViewAsTree();

      controller.toggleAllResultsCollapsed();
      controller.toggleAllResultsCollapsed();

      expect(container.read(provider).collapsedResultNodeKeys, isEmpty);
    },
  );

  test('toggle all files collapsed is a no-op without results', () {
    final service = _FakeWorkspaceSearchService();
    final container = ProviderContainer(
      overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final provider = workspaceSearchControllerProvider('workspace-1');
    final controller = container.read(provider.notifier);

    controller.toggleAllFilesCollapsed();

    expect(container.read(provider).collapsedResultNodeKeys, isEmpty);
  });

  test('clear search results clears replacement and filters', () async {
    final service = _FakeWorkspaceSearchService();
    final container = ProviderContainer(
      overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final provider = workspaceSearchControllerProvider('workspace-1');
    final controller = container.read(provider.notifier);
    controller.setQuery('/workspace', 'needle');
    controller.setReplacement('/workspace', 'replacement');
    controller.setIncludePattern('/workspace', 'lib/**');
    controller.setExcludePattern('/workspace', 'build/**');
    await controller.searchNow('/workspace');
    controller.toggleAllFilesCollapsed();

    controller.clearSearchResults();

    final state = container.read(provider);
    expect(state.query, isEmpty);
    expect(state.result, isNull);
    expect(state.error, isNull);
    expect(state.loading, isFalse);
    expect(state.collapsedResultNodeKeys, isEmpty);
    expect(state.replacement, isEmpty);
    expect(state.includePattern, isEmpty);
    expect(state.excludePattern, isEmpty);
  });

  test('search directory paths returns cumulative ancestors', () {
    expect(
      workspaceSearchDirectoryPaths('src/components/home/button.astro'),
      <String>['src', 'src/components', 'src/components/home'],
    );
  });

  test('replace requires a current preview result', () async {
    final service = _FakeWorkspaceSearchService();
    final container = ProviderContainer(
      overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final provider = workspaceSearchControllerProvider('workspace-1');
    final controller = container.read(provider.notifier);

    await expectLater(
      controller.replaceMatches(
        workspacePath: '/workspace',
        matchIds: const <String>[],
        editorSessions: EditorSessionRegistry(),
      ),
      throwsStateError,
    );

    expect(service.replaceCalls, 0);
    expect(container.read(provider).error, 'Run search before replacing.');
  });

  test('replace all is blocked when current preview is truncated', () async {
    final service = _FakeWorkspaceSearchService(result: _truncatedSearchResult);
    final container = ProviderContainer(
      overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final provider = workspaceSearchControllerProvider('workspace-1');
    final controller = container.read(provider.notifier);
    controller.setQuery('/workspace', 'needle');
    await controller.searchNow('/workspace');

    await expectLater(
      controller.replaceMatches(
        workspacePath: '/workspace',
        matchIds: const <String>[],
        editorSessions: EditorSessionRegistry(),
      ),
      throwsStateError,
    );

    expect(service.replaceCalls, 0);
    expect(
      container.read(provider).error,
      'Replace all is unavailable while results are truncated.',
    );
  });

  test(
    'selected replace is allowed when current preview is truncated',
    () async {
      final service = _FakeWorkspaceSearchService(
        result: _truncatedSearchResult,
      );
      final container = ProviderContainer(
        overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final provider = workspaceSearchControllerProvider('workspace-1');
      final controller = container.read(provider.notifier);
      controller.setQuery('/workspace', 'needle');
      await controller.searchNow('/workspace');

      await controller.replaceMatches(
        workspacePath: '/workspace',
        matchIds: const <String>['lib/main.dart:1:1:0'],
        editorSessions: EditorSessionRegistry(),
      );

      expect(service.replaceCalls, 1);
    },
  );

  test(
    'replace blocks dirty editor files before calling native layer',
    () async {
      final service = _FakeWorkspaceSearchService();
      final container = ProviderContainer(
        overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final provider = workspaceSearchControllerProvider('workspace-1');
      final controller = container.read(provider.notifier);
      controller.setQuery('/workspace', 'needle');
      controller.setReplacement('/workspace', 'replacement');
      await controller.searchNow('/workspace');

      final editorSessions = EditorSessionRegistry();
      editorSessions
          .documentFor('tab-1')
          .attachFile(
            workspacePath: '/workspace',
            relativePath: 'lib/main.dart',
          );
      editorSessions.register(
        'tab-1',
        EditorSessionHandle(
          isDirty: () => true,
          save: () async {},
          discard: () async {},
        ),
      );

      await expectLater(
        controller.replaceMatches(
          workspacePath: '/workspace',
          matchIds: const <String>[],
          editorSessions: editorSessions,
        ),
        throwsA(isA<WorkspaceSearchDirtyFilesException>()),
      );
      expect(service.replaceCalls, 0);
      expect(
        container.read(provider).error,
        'Save or discard lib/main.dart before replacing.',
      );
    },
  );
}

class _FakeWorkspaceSearchService extends WorkspaceSearchService {
  _FakeWorkspaceSearchService({
    native.WorkspaceSearchResult result = _searchResult,
  }) : this._(result);

  _FakeWorkspaceSearchService._(this._result);

  final native.WorkspaceSearchResult _result;
  int replaceCalls = 0;

  @override
  Future<native.WorkspaceSearchResult> search({
    required native.WorkspaceSearchOptions options,
  }) async {
    return _result;
  }

  @override
  Future<native.WorkspaceReplacePreview> previewReplace({
    required native.WorkspaceReplaceOptions options,
  }) async {
    return native.WorkspaceReplacePreview(
      result: _result,
      replacement: options.replacement,
      preserveCase: options.preserveCase,
    );
  }

  @override
  Future<native.WorkspaceReplaceResult> replaceMatches({
    required native.WorkspaceReplaceRequest request,
  }) async {
    replaceCalls += 1;
    return const native.WorkspaceReplaceResult(
      filesChanged: 1,
      matchesReplaced: 1,
      conflicts: <native.WorkspaceReplaceConflict>[],
    );
  }
}

const native.WorkspaceSearchResult _searchResult = native.WorkspaceSearchResult(
  totalMatches: 1,
  truncated: false,
  files: <native.WorkspaceSearchFileResult>[
    native.WorkspaceSearchFileResult(
      relativePath: 'lib/main.dart',
      contentToken: 'token',
      matches: <native.WorkspaceSearchMatch>[
        native.WorkspaceSearchMatch(
          id: 'lib/main.dart:1:1:0',
          line: 1,
          column: 1,
          matchLength: 6,
          lineContent: 'needle',
        ),
      ],
    ),
  ],
);

const native.WorkspaceSearchResult _multiFileSearchResult =
    native.WorkspaceSearchResult(
      totalMatches: 2,
      truncated: false,
      files: <native.WorkspaceSearchFileResult>[
        native.WorkspaceSearchFileResult(
          relativePath: 'lib/main.dart',
          contentToken: 'token-1',
          matches: <native.WorkspaceSearchMatch>[
            native.WorkspaceSearchMatch(
              id: 'lib/main.dart:1:1:0',
              line: 1,
              column: 1,
              matchLength: 6,
              lineContent: 'needle',
            ),
          ],
        ),
        native.WorkspaceSearchFileResult(
          relativePath: 'lib/other.dart',
          contentToken: 'token-2',
          matches: <native.WorkspaceSearchMatch>[
            native.WorkspaceSearchMatch(
              id: 'lib/other.dart:1:1:0',
              line: 1,
              column: 1,
              matchLength: 6,
              lineContent: 'needle',
            ),
          ],
        ),
      ],
    );

const native.WorkspaceSearchResult _treeSearchResult =
    native.WorkspaceSearchResult(
      totalMatches: 4,
      truncated: false,
      files: <native.WorkspaceSearchFileResult>[
        native.WorkspaceSearchFileResult(
          relativePath: 'src/components/home/button.astro',
          contentToken: 'token-1',
          matches: <native.WorkspaceSearchMatch>[
            native.WorkspaceSearchMatch(
              id: 'src/components/home/button.astro:1:1:0',
              line: 1,
              column: 1,
              matchLength: 6,
              lineContent: 'needle',
            ),
            native.WorkspaceSearchMatch(
              id: 'src/components/home/button.astro:2:1:1',
              line: 2,
              column: 1,
              matchLength: 6,
              lineContent: 'needle',
            ),
          ],
        ),
        native.WorkspaceSearchFileResult(
          relativePath: 'src/components/home/card.astro',
          contentToken: 'token-2',
          matches: <native.WorkspaceSearchMatch>[
            native.WorkspaceSearchMatch(
              id: 'src/components/home/card.astro:1:1:0',
              line: 1,
              column: 1,
              matchLength: 6,
              lineContent: 'needle',
            ),
          ],
        ),
        native.WorkspaceSearchFileResult(
          relativePath: 'bun.lock',
          contentToken: 'token-3',
          matches: <native.WorkspaceSearchMatch>[
            native.WorkspaceSearchMatch(
              id: 'bun.lock:1:1:0',
              line: 1,
              column: 1,
              matchLength: 6,
              lineContent: 'needle',
            ),
          ],
        ),
      ],
    );

const native.WorkspaceSearchResult _truncatedSearchResult =
    native.WorkspaceSearchResult(
      totalMatches: 1,
      truncated: true,
      files: <native.WorkspaceSearchFileResult>[
        native.WorkspaceSearchFileResult(
          relativePath: 'lib/main.dart',
          contentToken: 'token',
          matches: <native.WorkspaceSearchMatch>[
            native.WorkspaceSearchMatch(
              id: 'lib/main.dart:1:1:0',
              line: 1,
              column: 1,
              matchLength: 6,
              lineContent: 'needle',
            ),
          ],
        ),
      ],
    );
