import 'package:alera/src/features/browser/application/browser_closed_tabs_service.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_browser_tab_service.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates a browser tab with the selected profile and URL', () async {
    final repository = _BrowserTabRepository();
    final service = WorkspaceBrowserTabService(
      repository: repository,
      now: () => DateTime.utc(2026, 7, 27),
    );

    final tab = await service.createTab(
      'workspace-1',
      pageId: 'page-from-native-popup',
      profileId: 'research',
      initialUrl: ' https://example.com ',
    );

    expect(tab.kind, WorkspaceTabKind.browser);
    expect(tab.id, 'page-from-native-popup');
    expect(tab.title, 'New Tab');
    expect(tab.browserProfileId, 'research');
    expect(tab.browserUrl, 'https://example.com');
    expect(repository.tabs.single, same(tab));
  });

  test(
    'returns the authoritative record from the persistence boundary',
    () async {
      final repository = _BrowserTabRepository()
        ..upsertTransform = (tab) => tab.copyWith(title: 'Canonical Title');
      final service = WorkspaceBrowserTabService(repository: repository);

      final tab = await service.createTab('workspace-1');

      expect(tab.title, 'Canonical Title');
      expect(repository.tabs.single, same(tab));
    },
  );

  test('persists runtime state without replacing a manual title', () async {
    final repository = _BrowserTabRepository()
      ..tabs.add(
        WorkspaceTabRecord(
          id: 'browser-1',
          workspaceId: 'workspace-1',
          kind: .browser,
          title: 'Docs',
          createdAt: .utc(2026, 7, 27),
          updatedAt: .utc(2026, 7, 27),
          payload: const <String, Object?>{
            workspaceTabManualTitlePayloadKey: true,
            workspaceTabBrowserProfileIdPayloadKey: 'default',
          },
        ),
      );
    final service = WorkspaceBrowserTabService(repository: repository);

    final tab = await service.updateState(
      tabId: 'browser-1',
      profileId: 'research',
      url: 'https://docs.example.com',
      runtimeTitle: 'Example Docs',
    );

    expect(tab.title, 'Docs');
    expect(tab.browserRuntimeTitle, 'Example Docs');
    expect(tab.browserUrl, 'https://docs.example.com');
    expect(tab.browserProfileId, 'research');
  });

  test('uses the runtime title when no manual title exists', () async {
    final repository = _BrowserTabRepository()
      ..tabs.add(
        WorkspaceTabRecord(
          id: 'browser-1',
          workspaceId: 'workspace-1',
          kind: .browser,
          title: 'New Tab',
          createdAt: .utc(2026, 7, 27),
          updatedAt: .utc(2026, 7, 27),
        ),
      );
    final service = WorkspaceBrowserTabService(repository: repository);

    final tab = await service.updateState(
      tabId: 'browser-1',
      profileId: 'default',
      url: 'https://alera.dev',
      runtimeTitle: 'Alera',
    );

    expect(tab.title, 'Alera');
  });

  test('does not persist authentication callback URLs', () async {
    final repository = _BrowserTabRepository();
    final service = WorkspaceBrowserTabService(repository: repository);

    final tab = await service.createTab(
      'workspace-1',
      initialUrl: 'https://example.com/oauth/callback?code=secret',
    );

    expect(tab.browserUrl, isNull);
  });

  test('does not persist a page title from a sensitive URL', () async {
    final repository = _BrowserTabRepository()
      ..tabs.add(
        WorkspaceTabRecord(
          id: 'browser-1',
          workspaceId: 'workspace-1',
          kind: .browser,
          title: 'Safe Documentation',
          createdAt: .utc(2026, 7, 27),
          updatedAt: .utc(2026, 7, 27),
          payload: const <String, Object?>{
            workspaceTabBrowserProfileIdPayloadKey: 'default',
            workspaceTabBrowserUrlPayloadKey: 'https://example.com/docs',
            workspaceTabBrowserRuntimeTitlePayloadKey: 'Safe Documentation',
          },
        ),
      );
    final service = WorkspaceBrowserTabService(repository: repository);

    final tab = await service.updateState(
      tabId: 'browser-1',
      profileId: 'research',
      url: 'https://example.com/?auth=secret',
      runtimeTitle: 'Private Account',
    );

    expect(tab.title, 'Safe Documentation');
    expect(tab.browserUrl, isNull);
    expect(tab.browserRuntimeTitle, isNull);
  });

  test('does not persist a page title without its URL', () async {
    final repository = _BrowserTabRepository()
      ..tabs.add(
        WorkspaceTabRecord(
          id: 'browser-1',
          workspaceId: 'workspace-1',
          kind: .browser,
          title: 'Safe Documentation',
          createdAt: .utc(2026, 7, 27),
          updatedAt: .utc(2026, 7, 27),
          payload: const <String, Object?>{
            workspaceTabBrowserProfileIdPayloadKey: 'default',
            workspaceTabBrowserUrlPayloadKey: 'https://example.com/docs',
          },
        ),
      );
    final service = WorkspaceBrowserTabService(repository: repository);

    final tab = await service.updateState(
      tabId: 'browser-1',
      profileId: 'default',
      runtimeTitle: 'Private Account',
    );

    expect(tab.title, 'Safe Documentation');
    expect(tab.browserUrl, isNull);
    expect(tab.browserRuntimeTitle, isNull);
  });

  test('closes browser tabs through the recently closed catalog', () async {
    final repository = _BrowserTabRepository();
    final closedTabs = _BrowserClosedTabsService();
    final service = WorkspaceBrowserTabService(
      repository: repository,
      closedTabsService: closedTabs,
    );

    await service.closeTab('browser-1');

    expect(closedTabs.closedPageIds, <String>['browser-1']);
  });
}

class _BrowserClosedTabsService implements BrowserClosedTabsService {
  final List<String> closedPageIds = <String>[];

  @override
  Future<bool> close(String pageId) async {
    closedPageIds.add(pageId);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BrowserTabRepository implements WorkbenchRepository {
  final List<WorkspaceTabRecord> tabs = <WorkspaceTabRecord>[];
  WorkspaceTabRecord Function(WorkspaceTabRecord tab)? upsertTransform;

  @override
  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId) async {
    for (final tab in tabs) {
      if (tab.id == tabId) {
        return tab;
      }
    }
    return null;
  }

  @override
  Future<WorkspaceTabRecord> upsertWorkspaceTab(
    WorkspaceTabRecord tab, {
    bool manualRename = false,
  }) async {
    final saved = upsertTransform?.call(tab) ?? tab;
    tabs.removeWhere((candidate) => candidate.id == saved.id);
    tabs.add(saved);
    return saved;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
