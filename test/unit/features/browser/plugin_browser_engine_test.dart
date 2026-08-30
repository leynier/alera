import 'dart:async';

import 'package:alera/src/features/browser/domain/browser_automation.dart';
import 'package:alera/src/features/browser/domain/browser_engine_event.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/browser/infra/plugin_browser_engine.dart';
import 'package:alera_browser/alera_browser.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps clear, drag, and upload actions to the native client', () async {
    final platform = _ActionRecordingPlatform();
    final engine = PluginBrowserEngine(AleraBrowserClient(platform: platform));
    await engine.createPage(
      BrowserPage(
        pageId: 'page',
        workspaceId: 'workspace',
        profileId: 'default',
        initialUrl: Uri.parse('https://example.test'),
        createdAt: .utc(2026, 7, 27),
      ),
    );
    final snapshot = await engine.snapshot('page');
    final source = snapshot.nodes.first.target;
    final destination = snapshot.nodes.last.target;

    await engine.performAction(
      'page',
      BrowserAutomationAction(kind: .clear, target: source),
    );
    await engine.performAction(
      'page',
      BrowserAutomationAction(
        kind: .drag,
        target: source,
        secondaryTarget: destination,
      ),
    );
    await engine.performAction(
      'page',
      BrowserAutomationAction(
        kind: .upload,
        target: source,
        options: const <String, Object?>{
          'filePaths': <String>['/tmp/upload.txt'],
        },
      ),
    );

    expect(
      platform.actions.map((action) => action.kind),
      <AleraBrowserActionKind>[
        AleraBrowserActionKind.clear,
        AleraBrowserActionKind.drag,
        AleraBrowserActionKind.upload,
      ],
    );
    expect(platform.actions[1].targetElementRef, 'destination');
    expect(platform.actions[2].filePaths, <String>['/tmp/upload.txt']);
  });

  test('rejects drag actions without a fresh second target', () async {
    final platform = _ActionRecordingPlatform();
    final engine = PluginBrowserEngine(AleraBrowserClient(platform: platform));
    await engine.createPage(
      BrowserPage(
        pageId: 'page',
        workspaceId: 'workspace',
        profileId: 'default',
        initialUrl: Uri.parse('https://example.test'),
        createdAt: .utc(2026, 7, 27),
      ),
    );
    final snapshot = await engine.snapshot('page');

    await expectLater(
      engine.performAction(
        'page',
        BrowserAutomationAction(
          kind: .drag,
          target: snapshot.nodes.first.target,
        ),
      ),
      throwsA(isA<Exception>()),
    );
    expect(platform.actions, isEmpty);
  });

  test('navigation invalidates root snapshot references', () async {
    final platform = _ActionRecordingPlatform();
    final engine = PluginBrowserEngine(AleraBrowserClient(platform: platform));
    final subscription = engine.events.listen((_) {});
    await engine.createPage(
      BrowserPage(
        pageId: 'page',
        workspaceId: 'workspace',
        profileId: 'default',
        initialUrl: Uri.parse('https://example.test'),
        createdAt: .utc(2026, 7, 27),
      ),
    );
    final snapshot = await engine.snapshot('page');
    platform.eventController.add(
      AleraBrowserNavigationStarted(
        pageId: 'page',
        occurredAt: .utc(2026, 7, 27),
        url: Uri.parse('https://example.test/next'),
      ),
    );
    await Future<void>.delayed(.zero);

    await expectLater(
      engine.performAction(
        'page',
        BrowserAutomationAction(
          kind: .click,
          target: snapshot.nodes.first.target,
        ),
      ),
      throwsA(
        isA<BrowserFailure>().having(
          (failure) => failure.code,
          'code',
          BrowserErrorCode.staleAutomationReference,
        ),
      ),
    );
    expect(platform.actions, isEmpty);
    await subscription.cancel();
  });

  test('maps native navigation commits to the browser domain', () async {
    final platform = _ActionRecordingPlatform();
    final engine = PluginBrowserEngine(AleraBrowserClient(platform: platform));
    final nextEvent = engine.events
        .where((event) => event is BrowserNavigationCommitted)
        .cast<BrowserNavigationCommitted>()
        .first;
    final occurredAt = DateTime.utc(2026, 7, 27);
    final url = Uri.parse('https://example.test/committed');

    platform.eventController.add(
      AleraBrowserNavigationCommitted(
        pageId: 'page',
        occurredAt: occurredAt,
        url: url,
      ),
    );

    final event = await nextEvent;
    expect(event.pageId, 'page');
    expect(event.url, url);
    expect(event.occurredAt, occurredAt);
  });

  test('maps discovered and selected cookie source profiles', () async {
    final platform = _ActionRecordingPlatform();
    final engine = PluginBrowserEngine(AleraBrowserClient(platform: platform));
    final probeGesture = engine.beginCookieImportGesture();

    final statuses = await engine.probeCookieImportSources(probeGesture);

    expect(statuses.single.profileNames, <String>['Default', 'Profile 1']);
    final importGesture = engine.beginCookieImportGesture();
    await engine.importCookies(
      gesture: importGesture,
      profileId: 'target',
      source: .chrome,
      sourceProfileName: 'Profile 1',
    );
    final request =
        platform.importRequest as AleraBrowserNativeCookieImportRequest;
    expect(request.sourceProfileName, 'Profile 1');
  });

  test('rejects native cookie import without a profile selection', () async {
    final platform = _ActionRecordingPlatform();
    final engine = PluginBrowserEngine(AleraBrowserClient(platform: platform));

    await expectLater(
      engine.importCookies(
        gesture: engine.beginCookieImportGesture(),
        profileId: 'target',
        source: .chrome,
      ),
      throwsA(
        isA<BrowserFailure>().having(
          (failure) => failure.code,
          'code',
          BrowserErrorCode.invalidPayload,
        ),
      ),
    );
    expect(platform.importRequest, isNull);
  });
}

final class _ActionRecordingPlatform implements AleraBrowserPlatform {
  final StreamController<AleraBrowserEvent> eventController =
      StreamController<AleraBrowserEvent>.broadcast();
  final List<AleraBrowserAction> actions = <AleraBrowserAction>[];
  AleraBrowserCookieImportRequest? importRequest;

  @override
  Stream<AleraBrowserEvent> get events => eventController.stream;

  @override
  Future<AleraBrowserPage> createPage(AleraBrowserPageOptions options) async {
    return AleraBrowserPage(
      id: options.id!,
      profileId: options.profileId,
      url: options.initialUrl,
      isAttached: false,
      openerPageId: options.openerPageId,
      transient: options.transient,
    );
  }

  @override
  Future<AleraBrowserSnapshot> snapshot(
    String pageId,
    AleraBrowserSnapshotOptions options,
  ) async {
    return AleraBrowserSnapshot(
      pageId: pageId,
      namespace: 'test',
      pageGeneration: 1,
      snapshotId: 'native',
      url: Uri.parse('https://example.test'),
      title: 'Example',
      nodes: const <AleraBrowserSnapshotNode>[
        AleraBrowserSnapshotNode(
          ref: 'source',
          role: 'button',
          name: 'Source',
          depth: 0,
        ),
        AleraBrowserSnapshotNode(
          ref: 'destination',
          role: 'button',
          name: 'Destination',
          depth: 0,
        ),
      ],
      blockedCrossOriginFrameCount: 0,
    );
  }

  @override
  Future<void> performAction(String pageId, AleraBrowserAction action) async {
    actions.add(action);
  }

  @override
  Future<List<AleraBrowserCookieImportSourceStatus>>
  probeCookieImportSources() async =>
      const <AleraBrowserCookieImportSourceStatus>[
        AleraBrowserCookieImportSourceStatus(
          source: .chrome,
          supported: true,
          available: true,
          profileNames: <String>['Default', 'Profile 1'],
        ),
      ];

  @override
  Future<AleraBrowserCookieImportResult> importCookies(
    AleraBrowserCookieImportRequest request,
  ) async {
    importRequest = request;
    return AleraBrowserCookieImportResult(
      source: request is AleraBrowserNativeCookieImportRequest
          ? request.source
          : AleraBrowserCookieImportSource.manualJson,
      profileId: request.profileId,
      outcome: .imported,
      importedCount: 1,
      skippedCount: 0,
    );
  }

  @override
  Widget buildPageView(String pageId, {Key? key}) => SizedBox(key: key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
