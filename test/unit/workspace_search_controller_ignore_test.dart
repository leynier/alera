import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workspace_search_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_search_service.dart';
import 'package:alera/src/rust/api/workspace_search.dart' as native;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('include ignored defaults off and is sent to search options', () async {
    final service = _CapturingWorkspaceSearchService();
    final container = ProviderContainer(
      overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final provider = workspaceSearchControllerProvider('workspace-1');
    final controller = container.read(provider.notifier);
    controller.setQuery('/workspace', 'needle');
    await controller.searchNow('/workspace');

    expect(container.read(provider).includeIgnored, isFalse);
    expect(service.lastOptions?.includeIgnored, isFalse);
  });

  test(
    'toggle include ignored clears stale results and updates options',
    () async {
      final service = _CapturingWorkspaceSearchService();
      final container = ProviderContainer(
        overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final provider = workspaceSearchControllerProvider('workspace-1');
      final controller = container.read(provider.notifier);
      controller.setQuery('/workspace', 'needle');
      await controller.searchNow('/workspace');
      expect(container.read(provider).result, isNotNull);

      controller.toggleIncludeIgnored('/workspace');

      var state = container.read(provider);
      expect(state.includeIgnored, isTrue);
      expect(state.result, isNull);
      expect(state.loading, isTrue);

      await controller.searchNow('/workspace');

      state = container.read(provider);
      expect(state.result, isNotNull);
      expect(service.lastOptions?.includeIgnored, isTrue);
    },
  );

  test('clear search results preserves include ignored mode', () {
    final service = _CapturingWorkspaceSearchService();
    final container = ProviderContainer(
      overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    final provider = workspaceSearchControllerProvider('workspace-1');
    final controller = container.read(provider.notifier);

    controller.toggleIncludeIgnored('/workspace');
    controller.clearSearchResults();

    expect(container.read(provider).includeIgnored, isTrue);
  });
}

class _CapturingWorkspaceSearchService extends WorkspaceSearchService {
  native.WorkspaceSearchOptions? lastOptions;

  @override
  Future<native.WorkspaceSearchResult> search({
    required native.WorkspaceSearchOptions options,
  }) async {
    lastOptions = options;
    return _searchResult;
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
