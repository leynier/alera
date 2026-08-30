import 'dart:async';

import 'package:alera/src/features/browser/application/browser_session_registry.dart';
import 'package:alera/src/features/browser/domain/browser_automation.dart';
import 'package:alera/src/features/browser/domain/browser_engine_event.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_page_state.dart';
import 'package:alera/src/features/browser/domain/browser_navigation.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_browser_engine.dart';

void main() {
  late FakeBrowserEngine engine;
  late BrowserSessionRegistry registry;

  setUp(() {
    engine = FakeBrowserEngine();
    registry = BrowserSessionRegistry(
      engine: engine,
      readSearchEngine: () async => BrowserSearchEngine.duckDuckGo,
      now: () => DateTime.utc(2026, 1, 2),
    );
  });

  tearDown(() async {
    await registry.dispose();
    await engine.dispose();
  });

  test('deduplicates sessions and creates one native page', () async {
    final tab = _tab();

    final handles = await Future.wait(<Future<BrowserSessionHandle>>[
      registry.sessionFor(tab),
      registry.sessionFor(tab),
    ]);

    expect(identical(handles.first, handles.last), isTrue);
    expect(
      engine.calls.where((call) => call.startsWith('createPage:')),
      hasLength(1),
    );
    expect(handles.first.surfaceToken.pageId, tab.id);
  });

  test('attaches on first visibility and detaches after last lease', () async {
    final handle = await registry.sessionFor(_tab());

    final first = handle.acquireVisibility(.user);
    final second = handle.acquireVisibility(.automation);
    await Future.wait(<Future<void>>[first.ready, second.ready]);

    expect(
      engine.calls.where((call) => call.startsWith('attach:')),
      hasLength(1),
    );
    await first.dispose();
    expect(engine.calls.where((call) => call.startsWith('detach:')), isEmpty);
    await second.dispose();
    expect(
      engine.calls.where((call) => call.startsWith('detach:')),
      hasLength(1),
    );
  });

  test('search preference and engine events update the handle', () async {
    final handle = await registry.sessionFor(_tab());

    final target = await handle.loadUrl('flutter riverpod');
    expect(target.kind, BrowserNavigationKind.search);
    expect(engine.loadedUrl?.host, 'duckduckgo.com');

    engine.eventController.add(
      BrowserNavigationFinished(
        pageId: handle.pageId,
        occurredAt: .utc(2026, 1, 3),
        url: Uri.parse('https://example.com'),
        title: 'Example',
        canGoBack: true,
      ),
    );

    expect(handle.state.title, 'Example');
    expect(handle.state.loadPhase, BrowserLoadPhase.finished);
    expect(handle.state.canGoBack, isTrue);
  });

  test('overlay restoration runs in finally', () async {
    final handle = await registry.sessionFor(_tab());

    await expectLater(
      handle.withFlutterOverlay<void>(() async {
        throw StateError('dialog failed');
      }),
      throwsStateError,
    );

    expect(
      engine.calls.where((call) => call.startsWith('obscured:')).toList(),
      <String>['obscured:page-1:true', 'obscured:page-1:false'],
    );
  });

  test('overlapping overlays keep the native page obscured', () async {
    final handle = await registry.sessionFor(_tab());
    final first = Completer<void>();
    final second = Completer<void>();
    final firstOverlay = handle.withFlutterOverlay(() => first.future);
    final secondOverlay = handle.withFlutterOverlay(() => second.future);

    await Future.pause(.zero);
    expect(
      engine.calls.where((call) => call.startsWith('obscured:')).toList(),
      <String>['obscured:page-1:true'],
    );

    first.complete();
    await firstOverlay;
    expect(
      engine.calls.where((call) => call.startsWith('obscured:')).toList(),
      <String>['obscured:page-1:true'],
    );

    second.complete();
    await secondOverlay;
    expect(
      engine.calls.where((call) => call.startsWith('obscured:')).toList(),
      <String>['obscured:page-1:true', 'obscured:page-1:false'],
    );
  });

  test('tab drag and Flutter overlay share obscuration state', () async {
    final handle = await registry.sessionFor(_tab());
    final drag = handle.acquireObscuration(.tabDrag);
    await drag.ready;
    final overlayBarrier = Completer<void>();
    final overlay = handle.withFlutterOverlay(() => overlayBarrier.future);

    await Future.pause(.zero);
    await drag.dispose();
    expect(
      engine.calls.where((call) => call.startsWith('obscured:')).toList(),
      <String>['obscured:page-1:true'],
    );

    overlayBarrier.complete();
    await overlay;
    expect(
      engine.calls.where((call) => call.startsWith('obscured:')).toList(),
      <String>['obscured:page-1:true', 'obscured:page-1:false'],
    );
  });

  test('close waits for lifecycle leases', () async {
    final handle = await registry.sessionFor(_tab());
    final lease = handle.acquireLifecycle(.popup);
    var closed = false;
    final closing = handle.close().then((_) => closed = true);

    await Future.pause(.zero);
    expect(closed, isFalse);
    await lease.dispose();
    await closing;

    expect(closed, isTrue);
    expect(engine.calls, contains('close:page-1'));
  });

  test(
    'presentation visibility skips a session that started closing',
    () async {
      final handle = await registry.sessionFor(_tab());
      final lifecycle = handle.acquireLifecycle(.popup);
      final closing = handle.close();

      await Future.pause(.zero);

      expect(handle.tryAcquireVisibility(.user), isNull);
      expect(
        () => handle.acquireVisibility(.user),
        throwsA(
          isA<BrowserFailure>().having(
            (failure) => failure.code,
            'code',
            BrowserErrorCode.pageNotFound,
          ),
        ),
      );

      await lifecycle.dispose();
      await closing;
    },
  );

  test(
    'registry disposal does not close under an active native command',
    () async {
      final handle = await registry.sessionFor(_tab());
      final snapshot = Completer<BrowserAutomationSnapshot>();
      engine.snapshotCompleter = snapshot;
      final command = handle.snapshot();
      while (engine.lastSnapshotMaxNodes == null) {
        await Future.pause(.zero);
      }
      var disposed = false;
      final disposal = registry.dispose().then((_) => disposed = true);

      await Future.pause(.zero);
      expect(disposed, isFalse);
      expect(engine.calls, isNot(contains('close:page-1')));

      snapshot.complete(
        BrowserAutomationSnapshot(
          pageId: handle.pageId,
          snapshotId: 'snapshot',
          url: Uri.parse('https://example.com'),
          title: 'Example',
          nodes: const <BrowserAutomationNode>[],
          capturedAt: .utc(2026),
        ),
      );
      await command;
      await disposal;

      expect(engine.calls, contains('close:page-1'));
    },
  );

  test('close does not wait for a visible surface lease', () async {
    final handle = await registry.sessionFor(_tab());
    final visibility = handle.acquireVisibility(.user);
    await visibility.ready;

    await handle.close();

    expect(engine.calls, contains('close:page-1'));
    expect(registry.handleForPageId('page-1'), isNull);
    await visibility.dispose();
  });

  test('failed native close keeps the session retryable', () async {
    engine.closeFailuresRemaining = 1;
    final handle = await registry.sessionFor(_tab());

    await expectLater(handle.close(), throwsStateError);
    expect(registry.handleForPageId(handle.pageId), same(handle));

    await handle.close();
    expect(registry.handleForPageId(handle.pageId), isNull);
    expect(engine.calls.where((call) => call == 'close:page-1'), hasLength(2));
  });

  test(
    'session request waits for close and recreates the native page',
    () async {
      final first = await registry.sessionFor(_tab());
      final nativeClose = Completer<void>();
      engine.closePageCompleters[first.pageId] = nativeClose;
      final closing = first.close();
      while (!engine.calls.contains('close:page-1')) {
        await Future.pause(.zero);
      }

      var recreated = false;
      final replacement = registry.sessionFor(_tab()).then((handle) {
        recreated = true;
        return handle;
      });
      await Future.pause(.zero);
      expect(recreated, isFalse);

      nativeClose.complete();
      await closing;
      final second = await replacement;

      expect(identical(first, second), isFalse);
      expect(
        engine.calls.where((call) => call == 'createPage:page-1:false'),
        hasLength(2),
      );
    },
  );

  test(
    'workspace close releases only sessions owned by that workspace',
    () async {
      await registry.sessionFor(_tab());
      await registry.sessionFor(
        _tab(pageId: 'page-2', workspaceId: 'workspace-2'),
      );

      await registry.closeWorkspace('workspace-1');

      expect(registry.handleForPageId('page-1'), isNull);
      expect(registry.handleForPageId('page-2'), isNotNull);
      expect(engine.calls, contains('close:page-1'));
      expect(engine.calls, isNot(contains('close:page-2')));
    },
  );

  test(
    'reconciles persistent sessions against authoritative tab ids',
    () async {
      await registry.sessionFor(_tab());
      await registry.sessionFor(
        _tab(pageId: 'page-2', workspaceId: 'workspace-2'),
      );
      await registry.transientSessionFor(
        page: BrowserPage(
          pageId: 'popup',
          workspaceId: 'workspace-1',
          profileId: 'default',
          initialUrl: Uri.parse('about:blank'),
          createdAt: .utc(2026),
        ),
        openerPageId: 'page-1',
      );

      await registry.reconcilePersistentPages(<String>{'page-1'});

      expect(registry.handleForPageId('page-1'), isNotNull);
      expect(registry.handleForPageId('page-2'), isNull);
      expect(registry.handleForPageId('popup'), isNotNull);
    },
  );

  test(
    'materializes every persistent browser tab during reconciliation',
    () async {
      await registry.reconcilePersistentTabs(<WorkspaceTabRecord>[
        _tab(),
        _tab(pageId: 'page-2', workspaceId: 'workspace-2'),
      ]);

      expect(registry.handleForPageId('page-1'), isNotNull);
      expect(registry.handleForPageId('page-2'), isNotNull);
      expect(
        engine.calls,
        containsAll(<String>[
          'createPage:page-1:false',
          'createPage:page-2:false',
        ]),
      );

      await registry.reconcilePersistentTabs(<WorkspaceTabRecord>[
        _tab(pageId: 'page-2', workspaceId: 'workspace-2'),
      ]);

      expect(registry.handleForPageId('page-1'), isNull);
      expect(registry.handleForPageId('page-2'), isNotNull);
    },
  );

  test('latest reconciliation supersedes stale queued snapshots', () async {
    final reconciler = BrowserPersistentSessionReconciler(registry);
    addTearDown(reconciler.dispose);
    final blocker = Completer<void>();
    engine.createPageCompleters['blocker'] = blocker;
    reconciler.schedule(<WorkspaceTabRecord>[_tab(pageId: 'blocker')]);
    while (!engine.calls.contains('createPage:blocker:false')) {
      await Future.pause(.zero);
    }

    reconciler.schedule(const <WorkspaceTabRecord>[]);
    await registry.sessionFor(_tab());
    reconciler.schedule(<WorkspaceTabRecord>[_tab()]);
    blocker.complete();
    await reconciler.settled;

    expect(registry.handleForPageId('page-1'), isNotNull);
    expect(engine.calls, isNot(contains('close:page-1')));
    expect(registry.handleForPageId('blocker'), isNull);
  });
}

WorkspaceTabRecord _tab({
  String pageId = 'page-1',
  String workspaceId = 'workspace-1',
}) {
  return WorkspaceTabRecord(
    id: pageId,
    workspaceId: workspaceId,
    kind: .browser,
    title: 'New Tab',
    createdAt: .utc(2026),
    updatedAt: .utc(2026),
    payload: const <String, Object?>{
      workspaceTabBrowserProfileIdPayloadKey: 'default',
    },
  );
}
