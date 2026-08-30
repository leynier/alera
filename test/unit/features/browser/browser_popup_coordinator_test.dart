import 'package:alera/src/features/browser/application/browser_popup_coordinator.dart';
import 'package:alera/src/features/browser/application/browser_session_registry.dart';
import 'package:alera/src/features/browser/domain/browser_engine_event.dart';
import 'package:alera/src/features/browser/domain/browser_popup.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_browser_engine.dart';

void main() {
  late FakeBrowserEngine engine;
  late BrowserSessionRegistry registry;
  late List<WorkspaceTabRecord> createdTabs;
  late BrowserPopupCoordinator coordinator;

  setUp(() async {
    engine = FakeBrowserEngine();
    registry = BrowserSessionRegistry(engine: engine);
    createdTabs = <WorkspaceTabRecord>[];
    coordinator = BrowserPopupCoordinator(
      registry: registry,
      createWorkspaceTab:
          ({
            required String pageId,
            required String workspaceId,
            required String profileId,
            required String initialUrl,
          }) async {
            final tab = _tab(
              id: pageId,
              workspaceId: workspaceId,
              profileId: profileId,
              url: initialUrl,
            );
            createdTabs.add(tab);
            return tab;
          },
    );
    await registry.sessionFor(_tab());
  });

  tearDown(() async {
    await coordinator.dispose();
    await registry.dispose();
    await engine.dispose();
  });

  test('trusted user popup adopts and promotes the provisional page', () async {
    final decision = await coordinator.decide(
      _request(
        transientPageId: 'popup-1',
        url: Uri.parse('https://example.com/popup'),
      ),
    );

    expect(decision.targetPageId, 'popup-1');
    expect(createdTabs.single.id, 'popup-1');
    expect(createdTabs.single.workspaceId, 'workspace-1');
    expect(createdTabs.single.browserProfileId, 'work');
    expect(engine.calls, contains('adopt:popup-1'));
    expect(engine.calls, contains('promote:popup-1'));
  });

  test(
    'opener-dependent popup remains transient and is not persisted',
    () async {
      final decision = await coordinator.decide(
        _request(
          transientPageId: 'popup-2',
          requiresOpener: true,
          userInitiated: false,
        ),
      );

      expect(decision.targetPageId, 'popup-2');
      expect(createdTabs, isEmpty);
      expect(registry.handleForPageId('popup-2')?.isTransient, isTrue);
      expect(coordinator.debugTransientPageCount, 1);
    },
  );

  test('closing the opener closes its dependent transient popup', () async {
    await coordinator.decide(
      _request(
        transientPageId: 'popup-opener-close',
        requiresOpener: true,
        userInitiated: false,
      ),
    );

    await registry.closePage('page-1').timeout(const Duration(seconds: 1));

    expect(registry.handleForPageId('page-1'), isNull);
    expect(registry.handleForPageId('popup-opener-close'), isNull);
    expect(coordinator.debugTransientPageCount, 0);
    expect(createdTabs, isEmpty);
    expect(engine.calls, contains('close:popup-opener-close'));
    expect(engine.calls, contains('close:page-1'));
  });

  test('workspace close does not wait on dependent transient popups', () async {
    await coordinator.decide(
      _request(
        transientPageId: 'popup-workspace-close',
        requiresOpener: true,
        userInitiated: false,
      ),
    );

    await registry
        .closeWorkspace('workspace-1')
        .timeout(const Duration(seconds: 1));

    expect(registry.handleForPageId('page-1'), isNull);
    expect(registry.handleForPageId('popup-workspace-close'), isNull);
    expect(coordinator.debugTransientPageCount, 0);
    expect(createdTabs, isEmpty);
  });

  test(
    'native popup close reconciles without a duplicate close call',
    () async {
      await coordinator.decide(
        _request(
          transientPageId: 'popup-native-close',
          requiresOpener: true,
          userInitiated: false,
        ),
      );
      final closed = registry.events.firstWhere(
        (event) =>
            event.kind == BrowserRegistryEventKind.closed &&
            event.pageId == 'popup-native-close',
      );
      engine.pages.remove('popup-native-close');
      engine.eventController.add(
        BrowserPageClosed(
          pageId: 'popup-native-close',
          occurredAt: DateTime.utc(2026),
        ),
      );

      await closed.timeout(const Duration(seconds: 1));

      expect(registry.handleForPageId('popup-native-close'), isNull);
      expect(coordinator.debugTransientPageCount, 0);
      expect(
        engine.calls.where((call) => call == 'close:popup-native-close'),
        isEmpty,
      );
      expect(createdTabs, isEmpty);
    },
  );

  test('native opener close also closes its dependent popup', () async {
    await coordinator.decide(
      _request(
        transientPageId: 'popup-native-opener-close',
        requiresOpener: true,
        userInitiated: false,
      ),
    );
    final popupClosed = registry.events.firstWhere(
      (event) =>
          event.kind == BrowserRegistryEventKind.closed &&
          event.pageId == 'popup-native-opener-close',
    );
    final openerClosed = registry.events.firstWhere(
      (event) =>
          event.kind == BrowserRegistryEventKind.closed &&
          event.pageId == 'page-1',
    );
    engine.pages.remove('page-1');
    engine.eventController.add(
      BrowserPageClosed(pageId: 'page-1', occurredAt: DateTime.utc(2026)),
    );

    await Future.wait(<Future<BrowserRegistryEvent>>[popupClosed, openerClosed])
        .timeout(const Duration(seconds: 1));

    expect(registry.handleForPageId('page-1'), isNull);
    expect(registry.handleForPageId('popup-native-opener-close'), isNull);
    expect(coordinator.debugTransientPageCount, 0);
    expect(engine.calls, contains('close:popup-native-opener-close'));
    expect(engine.calls.where((call) => call == 'close:page-1'), isEmpty);
  });

  test('non-web popup is denied without adopting provisional page', () async {
    final decision = await coordinator.decide(
      _request(
        transientPageId: 'popup-3',
        url: Uri.parse('javascript:alert(1)'),
      ),
    );

    expect(decision.accepted, isFalse);
    expect(engine.calls, isNot(contains('adopt:popup-3')));
  });
}

BrowserPopupRequest _request({
  required String transientPageId,
  Uri? url,
  bool userInitiated = true,
  bool requiresOpener = false,
}) {
  return BrowserPopupRequest(
    requestId: 'request',
    openerPageId: 'page-1',
    transientPageId: transientPageId,
    url: url,
    userInitiated: userInitiated,
    trusted: true,
    requiresOpener: requiresOpener,
    requestedAt: DateTime.utc(2026),
  );
}

WorkspaceTabRecord _tab({
  String id = 'page-1',
  String workspaceId = 'workspace-1',
  String profileId = 'work',
  String? url,
}) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: workspaceId,
    kind: WorkspaceTabKind.browser,
    title: 'New Tab',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    payload: <String, Object?>{
      workspaceTabBrowserProfileIdPayloadKey: profileId,
      workspaceTabBrowserUrlPayloadKey: ?url,
    },
  );
}
