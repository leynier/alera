import 'dart:async';

import 'package:alera/src/features/browser/application/browser_engine.dart';
import 'package:alera/src/features/browser/domain/browser_automation.dart';
import 'package:alera/src/features/browser/domain/browser_cookie.dart';
import 'package:alera/src/features/browser/domain/browser_cookie_import.dart';
import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:alera/src/features/browser/domain/browser_engine_event.dart';
import 'package:alera/src/features/browser/domain/browser_engine_models.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';
import 'package:alera_browser/alera_browser.dart';

part 'plugin_browser_engine_mappers.dart';
part 'plugin_browser_engine_profiles.dart';

final class PluginBrowserEngine implements BrowserEngine {
  PluginBrowserEngine(this.client, {DateTime Function()? now})
    : _now = now ?? _defaultNow {
    _profiles = _PluginBrowserProfiles(client: client, now: _now);
    _events = client.events
        .map<BrowserEngineEvent?>((event) {
          if (event is AleraBrowserNavigationStarted) {
            _latestSnapshotIds.remove(event.pageId);
          }
          return _eventFromPlugin(event);
        })
        .where((event) => event != null)
        .map((event) => event!)
        .asBroadcastStream();
  }

  final AleraBrowserClient client;
  final DateTime Function() _now;
  final Map<String, BrowserPage> _pages = <String, BrowserPage>{};
  final Map<String, String> _latestSnapshotIds = <String, String>{};
  late final _PluginBrowserProfiles _profiles;
  var _snapshotSequence = 0;
  late final Stream<BrowserEngineEvent> _events;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  @override
  Stream<BrowserEngineEvent> get events => _events;

  @override
  Future<BrowserEngineCapabilities> probeCapabilities() {
    return _run(() async {
      final value = await client.probeCapabilities();
      return BrowserEngineCapabilities(
        engine: value.engine.name,
        engineVersion: value.engineVersion,
        engineAvailable: value.engineAvailable,
        pageSurface: value.pageSurface,
        isolatedProfiles: value.isolatedProfiles,
        ephemeralProfiles: value.ephemeralProfiles,
        deterministicPageClose: value.deterministicPageClose,
        navigation: value.navigation,
        navigationEvents: value.navigationEvents,
        javascript: value.javascript,
        basicCookies: value.basicCookies,
        fullCookies: value.fullCookies,
        permissionCallbacks: value.permissionCallbacks,
        tlsCallbacks: value.tlsCallbacks,
        tlsTrustScope: value.tlsTrustScope.name,
        popupCallbacks: value.popupCallbacks,
        downloadCallbacks: value.downloadCallbacks,
        domSnapshot: value.domSnapshot,
        domActions: value.domActions,
        viewportScreenshot: value.viewportScreenshot,
        fullPageScreenshot: value.fullPageScreenshot,
        pdf: value.pdf,
        flutterOverlayOcclusion: value.flutterOverlayOcclusion,
        atomicCookieImport: value.atomicCookieImport,
        manualJsonCookieImport: value.manualJsonCookieImport,
        linuxGtkOverlay: value.linuxGtkOverlay == true,
        nativeCookieImportSources: Set<String>.unmodifiable(
          value.nativeCookieImportSources,
        ),
        requiredNativeCookieImportSources: Set<String>.unmodifiable(
          value.requiredNativeCookieImportSources,
        ),
        limitations: List<String>.unmodifiable(value.limitations),
      );
    });
  }

  @override
  Future<List<BrowserProfile>> listProfiles() => _profiles.list();

  @override
  Future<BrowserProfile> createProfile({
    required String id,
    required String label,
    required BrowserProfileKind kind,
    required bool persistent,
  }) => _profiles.create(
    id: id,
    label: label,
    kind: kind,
    persistent: persistent,
  );

  @override
  Future<void> deleteProfile(String profileId) => _profiles.delete(profileId);

  @override
  BrowserCookieImportGesture beginCookieImportGesture() =>
      _profiles.beginImportGesture();

  @override
  Future<List<BrowserCookieImportSourceStatus>> probeCookieImportSources(
    BrowserCookieImportGesture gesture,
  ) => _profiles.probeImportSources(gesture);

  @override
  Future<BrowserCookieImportResult> importCookies({
    required BrowserCookieImportGesture gesture,
    required String profileId,
    required BrowserImportSourceFamily source,
    String? sourceProfileName,
    String? manualJson,
  }) => _profiles.import(
    gesture: gesture,
    profileId: profileId,
    source: source,
    sourceProfileName: sourceProfileName,
    manualJson: manualJson,
  );

  @override
  Future<void> createPage(
    BrowserPage page, {
    String? openerPageId,
    bool transient = false,
  }) {
    return _run(() async {
      await client.createPage(
        AleraBrowserPageOptions(
          id: page.pageId,
          profileId: page.profileId,
          initialUrl: page.initialUrl,
          openerPageId: openerPageId,
          transient: transient,
        ),
      );
      _pages[page.pageId] = page;
    });
  }

  @override
  Future<void> adoptTransientPage(BrowserPage page) {
    return _run(() async {
      await client.adoptTransientPage(page.pageId, profileId: page.profileId);
      _pages[page.pageId] = page;
    });
  }

  @override
  Future<void> promoteTransientPage(String pageId) =>
      _run(() => client.promoteTransientPage(pageId));

  @override
  Future<void> attachPage(String pageId) =>
      _run(() => client.attachPage(pageId, leaseId: 'registry'));

  @override
  Future<void> detachPage(String pageId) =>
      _run(() => client.detachPage(pageId, leaseId: 'registry'));

  @override
  Future<void> setPageObscured(String pageId, {required bool obscured}) =>
      _run(() => client.setPageObscured(pageId, obscured));

  @override
  Future<void> closePage(String pageId) {
    return _run(() async {
      await client.closePage(pageId);
      _pages.remove(pageId);
      _latestSnapshotIds.remove(pageId);
    });
  }

  @override
  Future<void> loadUrl(String pageId, Uri url) =>
      _run(() => client.loadUrl(pageId, url));

  @override
  Future<void> back(String pageId) => _run(() => client.goBack(pageId));

  @override
  Future<void> forward(String pageId) => _run(() => client.goForward(pageId));

  @override
  Future<void> reload(String pageId) => _run(() => client.reload(pageId));

  @override
  Future<void> stop(String pageId) => _run(() => client.stop(pageId));

  @override
  Future<Object?> evaluateJavaScript(String pageId, String expression) =>
      _run(() => client.evaluateJavaScript(pageId, expression));

  @override
  Future<List<BrowserCookie>> getCookies(String pageId, {Uri? url}) {
    return _run(() async {
      final page = _requiredPage(pageId);
      final targetUrl = url ?? await client.currentUrl(pageId);
      if (targetUrl == null) {
        return const <BrowserCookie>[];
      }
      final values = await client.getCookies(page.profileId, targetUrl);
      return <BrowserCookie>[
        for (final value in values) _cookieFromPlugin(value),
      ];
    });
  }

  @override
  Future<void> setCookie(String pageId, BrowserCookie cookie) {
    final page = _requiredPage(pageId);
    return _run(
      () => client.setCookie(page.profileId, _cookieToPlugin(cookie)),
    );
  }

  @override
  Future<void> deleteCookies(
    String pageId, {
    String? name,
    Uri? url,
    String? domain,
    String? path,
  }) {
    final page = _requiredPage(pageId);
    return _run(() async {
      await client.deleteCookies(
        page.profileId,
        AleraBrowserCookieFilter(
          name: name,
          url: url,
          domain: domain,
          path: path,
        ),
      );
    });
  }

  @override
  Future<BrowserAutomationSnapshot> snapshot(
    String pageId, {
    bool interactiveOnly = false,
    int maxNodes = 500,
  }) {
    return _run(() async {
      final value = await client.snapshot(
        pageId,
        options: AleraBrowserSnapshotOptions(
          interactiveOnly: interactiveOnly,
          maxNodes: maxNodes,
        ),
      );
      final snapshotId = '${++_snapshotSequence}';
      _latestSnapshotIds[pageId] = snapshotId;
      return BrowserAutomationSnapshot(
        pageId: pageId,
        snapshotId: snapshotId,
        url: value.url,
        title: value.title,
        nodes: <BrowserAutomationNode>[
          for (final node in value.nodes)
            BrowserAutomationNode(
              target: BrowserAutomationRef(
                pageId: pageId,
                snapshotId: snapshotId,
                ref: node.ref,
              ),
              role: node.role,
              name: node.name,
              value: node.value,
              depth: node.depth,
              disabled: node.disabled,
              checked: node.checked,
            ),
        ],
        capturedAt: _now(),
        truncated: value.truncated,
      );
    });
  }

  @override
  Future<void> performAction(String pageId, BrowserAutomationAction action) {
    return _run(() async {
      final target = action.target;
      if (target == null) {
        throw const BrowserFailure(
          code: BrowserErrorCode.invalidPayload,
          message: 'The browser action requires a target.',
          recoverable: true,
        );
      }
      target.validateFor(
        pageId: pageId,
        snapshotId: _latestSnapshotIds[pageId] ?? '',
      );
      final secondaryTarget = action.secondaryTarget;
      secondaryTarget?.validateFor(
        pageId: pageId,
        snapshotId: _latestSnapshotIds[pageId] ?? '',
      );
      if (action.kind == BrowserAutomationActionKind.drag &&
          secondaryTarget == null) {
        throw const BrowserFailure(
          code: BrowserErrorCode.invalidPayload,
          message: 'The browser drag action requires a second target.',
          recoverable: true,
        );
      }
      final kind = _actionKindToPlugin(action.kind);
      await client.performAction(
        pageId,
        AleraBrowserAction(
          kind: kind,
          elementRef: target.ref,
          value: action.value,
          values: _actionValues(action),
          targetElementRef: secondaryTarget?.ref,
          filePaths: _actionFilePaths(action),
        ),
      );
    });
  }

  @override
  Future<BrowserArtifactResult> captureScreenshot(
    String pageId, {
    required String destinationPath,
    required DateTime expiresAt,
    bool fullPage = false,
  }) {
    return _run(() async {
      final value = await client.captureScreenshotToFile(
        pageId,
        destinationPath: destinationPath,
        options: AleraBrowserScreenshotOptions(fullPage: fullPage),
      );
      return _artifactFromPlugin(value, expiresAt);
    });
  }

  @override
  Future<BrowserArtifactResult> printToPdf(
    String pageId, {
    required String destinationPath,
    required DateTime expiresAt,
  }) {
    return _run(() async {
      final value = await client.printToPdfFile(
        pageId,
        destinationPath: destinationPath,
      );
      return _artifactFromPlugin(value, expiresAt);
    });
  }

  @override
  Future<void> answerPermission(
    BrowserPermissionRequest request,
    BrowserPermissionDecision decision,
  ) => throw const BrowserFailure(
    code: BrowserErrorCode.unsupportedCapability,
    message: 'Permission decisions must be answered in the engine callback.',
  );

  @override
  Future<void> answerCertificateChallenge(
    String challengeId, {
    required bool proceed,
  }) => throw const BrowserFailure(
    code: BrowserErrorCode.unsupportedCapability,
    message: 'TLS decisions must be answered in the engine callback.',
  );

  @override
  Future<void> answerPopup(String requestId, {required bool allow}) =>
      throw const BrowserFailure(
        code: BrowserErrorCode.unsupportedCapability,
        message: 'Popup decisions must be answered in the engine callback.',
      );

  BrowserPage _requiredPage(String pageId) {
    final page = _pages[pageId];
    if (page == null) {
      throw BrowserFailure(
        code: BrowserErrorCode.pageNotFound,
        message: 'Browser page $pageId was not found.',
        recoverable: true,
      );
    }
    return page;
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on BrowserFailure {
      rethrow;
    } on AleraBrowserException catch (error) {
      throw _failureFromPlugin(error);
    }
  }
}
