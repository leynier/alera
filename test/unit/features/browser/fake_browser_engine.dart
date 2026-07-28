import 'dart:async';

import 'package:alera/src/features/browser/application/browser_engine.dart';
import 'package:alera/src/features/browser/domain/browser_automation.dart';
import 'package:alera/src/features/browser/domain/browser_cookie.dart';
import 'package:alera/src/features/browser/domain/browser_cookie_import.dart';
import 'package:alera/src/features/browser/domain/browser_engine_event.dart';
import 'package:alera/src/features/browser/domain/browser_engine_models.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';

final class FakeBrowserEngine implements BrowserEngine {
  final StreamController<BrowserEngineEvent> eventController =
      StreamController<BrowserEngineEvent>.broadcast(sync: true);
  final List<String> calls = <String>[];
  final Map<String, BrowserPage> pages = <String, BrowserPage>{};
  BrowserEngineCapabilities capabilities = stableBrowserCapabilities;
  BrowserCookieImportResult? importResult;
  Object? createProfileError;
  Object? deleteProfileError;
  Completer<BrowserEngineCapabilities>? capabilitiesCompleter;
  final Map<String, Completer<void>> createPageCompleters =
      <String, Completer<void>>{};
  final Map<String, Completer<void>> closePageCompleters =
      <String, Completer<void>>{};
  Completer<void>? navigationCompleter;
  Completer<BrowserAutomationSnapshot>? snapshotCompleter;
  Completer<BrowserArtifactResult>? screenshotCompleter;
  int closeFailuresRemaining = 0;
  bool? lastSnapshotInteractiveOnly;
  int? lastSnapshotMaxNodes;
  Uri? loadedUrl;

  @override
  Stream<BrowserEngineEvent> get events => eventController.stream;

  @override
  Future<BrowserEngineCapabilities> probeCapabilities() =>
      capabilitiesCompleter?.future ??
      Future<BrowserEngineCapabilities>.value(capabilities);

  @override
  Future<List<BrowserProfile>> listProfiles() async => const <BrowserProfile>[];

  @override
  Future<BrowserProfile> createProfile({
    required String id,
    required String label,
    required BrowserProfileKind kind,
    required bool persistent,
  }) async {
    calls.add('createProfile:$id:$persistent');
    if (createProfileError case final error?) {
      throw error;
    }
    return BrowserProfile(
      id: id,
      label: label,
      kind: kind,
      persistent: persistent,
      createdAt: DateTime.utc(2026),
    );
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    calls.add('deleteProfile:$profileId');
    if (deleteProfileError case final error?) {
      throw error;
    }
  }

  @override
  BrowserCookieImportGesture beginCookieImportGesture() =>
      BrowserCookieImportGesture(id: 'gesture', issuedAt: DateTime.utc(2026));

  @override
  Future<List<BrowserCookieImportSourceStatus>> probeCookieImportSources(
    BrowserCookieImportGesture gesture,
  ) async => const <BrowserCookieImportSourceStatus>[];

  @override
  Future<BrowserCookieImportResult> importCookies({
    required BrowserCookieImportGesture gesture,
    required String profileId,
    required BrowserImportSourceFamily source,
    String? sourceProfileName,
    String? manualJson,
  }) async {
    calls.add('importCookies:$profileId:${source.name}:$sourceProfileName');
    return importResult ??
        BrowserCookieImportResult(
          source: source,
          profileId: profileId,
          outcome: BrowserCookieImportOutcome.imported,
          importedCount: 1,
          skippedCount: 0,
        );
  }

  @override
  Future<void> createPage(
    BrowserPage page, {
    String? openerPageId,
    bool transient = false,
  }) async {
    calls.add('createPage:${page.pageId}:$transient');
    pages[page.pageId] = page;
    await createPageCompleters[page.pageId]?.future;
  }

  @override
  Future<void> adoptTransientPage(BrowserPage page) async {
    calls.add('adopt:${page.pageId}');
    pages[page.pageId] = page;
  }

  @override
  Future<void> promoteTransientPage(String pageId) async {
    calls.add('promote:$pageId');
  }

  @override
  Future<void> attachPage(String pageId) async {
    calls.add('attach:$pageId');
  }

  @override
  Future<void> detachPage(String pageId) async {
    calls.add('detach:$pageId');
  }

  @override
  Future<void> setPageObscured(String pageId, {required bool obscured}) async {
    calls.add('obscured:$pageId:$obscured');
  }

  @override
  Future<void> closePage(String pageId) async {
    calls.add('close:$pageId');
    if (closeFailuresRemaining > 0) {
      closeFailuresRemaining -= 1;
      throw StateError('close failed');
    }
    await closePageCompleters[pageId]?.future;
    pages.remove(pageId);
  }

  @override
  Future<void> loadUrl(String pageId, Uri url) async {
    calls.add('load:$pageId');
    loadedUrl = url;
    await navigationCompleter?.future;
  }

  @override
  Future<void> back(String pageId) async {
    calls.add('back:$pageId');
    await navigationCompleter?.future;
  }

  @override
  Future<void> forward(String pageId) async {
    calls.add('forward:$pageId');
    await navigationCompleter?.future;
  }

  @override
  Future<void> reload(String pageId) async {
    calls.add('reload:$pageId');
    await navigationCompleter?.future;
  }

  @override
  Future<void> stop(String pageId) async => calls.add('stop:$pageId');

  @override
  Future<Object?> evaluateJavaScript(String pageId, String expression) async =>
      <String, Object?>{'expression': expression};

  @override
  Future<List<BrowserCookie>> getCookies(String pageId, {Uri? url}) async =>
      const <BrowserCookie>[];

  @override
  Future<void> setCookie(String pageId, BrowserCookie cookie) async {}

  @override
  Future<void> deleteCookies(
    String pageId, {
    String? name,
    Uri? url,
    String? domain,
    String? path,
  }) async {
    calls.add('deleteCookies:$pageId');
  }

  @override
  Future<BrowserAutomationSnapshot> snapshot(
    String pageId, {
    bool interactiveOnly = false,
    int maxNodes = 500,
  }) {
    lastSnapshotInteractiveOnly = interactiveOnly;
    lastSnapshotMaxNodes = maxNodes;
    final snapshot = BrowserAutomationSnapshot(
      pageId: pageId,
      snapshotId: 'snapshot',
      url: Uri.parse('https://example.com'),
      title: 'Example',
      nodes: <BrowserAutomationNode>[
        BrowserAutomationNode(
          target: BrowserAutomationRef(
            pageId: pageId,
            snapshotId: 'snapshot',
            ref: 'e1',
          ),
          role: 'button',
          name: 'Submit',
          depth: 0,
        ),
      ],
      capturedAt: DateTime.utc(2026),
    );
    return snapshotCompleter?.future ??
        Future<BrowserAutomationSnapshot>.value(snapshot);
  }

  @override
  Future<void> performAction(
    String pageId,
    BrowserAutomationAction action,
  ) async {
    calls.add('action:$pageId:${action.kind.name}');
  }

  @override
  Future<BrowserArtifactResult> captureScreenshot(
    String pageId, {
    required String destinationPath,
    required DateTime expiresAt,
    bool fullPage = false,
  }) async {
    calls.add('screenshot:$destinationPath:$fullPage');
    if (screenshotCompleter case final completer?) {
      return completer.future;
    }
    return BrowserArtifactResult(
      path: destinationPath,
      mimeType: 'image/png',
      sizeBytes: 10,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<BrowserArtifactResult> printToPdf(
    String pageId, {
    required String destinationPath,
    required DateTime expiresAt,
  }) async {
    calls.add('pdf:$destinationPath');
    return BrowserArtifactResult(
      path: destinationPath,
      mimeType: 'application/pdf',
      sizeBytes: 10,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<void> answerPermission(
    BrowserPermissionRequest request,
    BrowserPermissionDecision decision,
  ) async {}

  @override
  Future<void> answerCertificateChallenge(
    String challengeId, {
    required bool proceed,
  }) async {}

  @override
  Future<void> answerPopup(String requestId, {required bool allow}) async {}

  Future<void> dispose() => eventController.close();
}

const BrowserEngineCapabilities stableBrowserCapabilities =
    BrowserEngineCapabilities(
      engine: 'test',
      engineAvailable: true,
      pageSurface: true,
      isolatedProfiles: true,
      ephemeralProfiles: true,
      deterministicPageClose: true,
      navigation: true,
      navigationEvents: true,
      javascript: true,
      basicCookies: true,
      fullCookies: true,
      permissionCallbacks: true,
      tlsCallbacks: true,
      popupCallbacks: true,
      downloadCallbacks: true,
      domSnapshot: true,
      domActions: true,
      viewportScreenshot: true,
      fullPageScreenshot: true,
      pdf: true,
      flutterOverlayOcclusion: true,
      atomicCookieImport: true,
      manualJsonCookieImport: true,
      nativeCookieImportSources: <String>{'chrome', 'manualJson'},
      requiredNativeCookieImportSources: <String>{'chrome', 'manualJson'},
    );
