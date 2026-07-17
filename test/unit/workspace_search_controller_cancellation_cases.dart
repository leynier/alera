part of 'workspace_search_controller_test.dart';

void _registerWorkspaceSearchCancellationTests() {
  test('search input changes cancel the obsolete native request', () async {
    final service = _BlockingWorkspaceSearchService();
    final container = ProviderContainer(
      overrides: [workspaceSearchServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);
    final controller = container.read(
      workspaceSearchControllerProvider('workspace-1').notifier,
    );
    controller.setQuery('/workspace', 'first');
    final firstSearch = controller.searchNow('/workspace');
    await service.started.future;

    controller.setQuery('/workspace', 'second');

    expect(service.cancelledRequestIds, [service.requestId]);
    service.complete();
    await firstSearch;
  });
}

class _BlockingWorkspaceSearchService extends WorkspaceSearchService {
  final Completer<void> started = Completer<void>();
  final Completer<native.WorkspaceSearchResult> _result =
      Completer<native.WorkspaceSearchResult>();
  final List<String> cancelledRequestIds = <String>[];
  String? requestId;

  @override
  Future<native.WorkspaceSearchResult> search({
    required native.WorkspaceSearchOptions options,
    required String requestId,
  }) {
    this.requestId = requestId;
    started.complete();
    return _result.future;
  }

  @override
  Future<void> cancel({required String requestId}) async {
    cancelledRequestIds.add(requestId);
  }

  void complete() {
    _result.complete(_searchResult);
  }
}
