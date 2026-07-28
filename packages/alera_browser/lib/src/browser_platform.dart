import 'package:flutter/widgets.dart';

import 'browser_capabilities.dart';
import 'browser_cookie_import.dart';
import 'browser_events.dart';
import 'browser_models.dart';

/// Injectable platform boundary used by the public client and contract tests.
abstract interface class AleraBrowserPlatform {
  Stream<AleraBrowserEvent> get events;

  Future<AleraBrowserCapabilities> probeCapabilities();

  Future<AleraBrowserProfile> createProfile(AleraBrowserProfileOptions options);

  Future<List<AleraBrowserProfile>> listProfiles();

  Future<void> deleteProfile(String profileId);

  Future<AleraBrowserPage> createPage(AleraBrowserPageOptions options);

  Future<AleraBrowserPage> adoptTransientPage(
    String pageId, {
    required String profileId,
  });

  Future<AleraBrowserPage> promoteTransientPage(String pageId);

  Future<void> attachPage(String pageId);

  Future<void> detachPage(String pageId);

  Future<void> setPageObscured(String pageId, bool obscured);

  Future<void> closePage(String pageId);

  Widget buildPageView(String pageId, {Key? key});

  Future<void> loadUrl(String pageId, Uri url, {Map<String, String> headers});

  Future<Uri?> currentUrl(String pageId);

  Future<String?> title(String pageId);

  Future<bool> canGoBack(String pageId);

  Future<bool> canGoForward(String pageId);

  Future<void> goBack(String pageId);

  Future<void> goForward(String pageId);

  Future<void> reload(String pageId);

  Future<void> stop(String pageId);

  Future<Object?> evaluateJavaScript(String pageId, String script);

  Future<List<AleraBrowserCookie>> getCookies(String profileId, Uri url);

  Future<void> setCookie(String profileId, AleraBrowserCookie cookie);

  Future<int> deleteCookies(String profileId, AleraBrowserCookieFilter filter);

  Future<AleraBrowserSnapshot> snapshot(
    String pageId,
    AleraBrowserSnapshotOptions options,
  );

  Future<void> performAction(String pageId, AleraBrowserAction action);

  Future<void> waitFor(
    String pageId,
    AleraBrowserWaitCondition condition, {
    required Duration timeout,
  });

  Future<AleraBrowserArtifact> captureScreenshotToFile(
    String pageId,
    String destinationPath,
    AleraBrowserScreenshotOptions options,
  );

  Future<AleraBrowserArtifact> printToPdfFile(
    String pageId,
    String destinationPath,
    AleraBrowserPdfOptions options,
  );

  Future<List<AleraBrowserCookieImportSourceStatus>> probeCookieImportSources();

  Future<AleraBrowserCookieImportResult> importCookies(
    AleraBrowserCookieImportRequest request,
  );

  Future<void> dispose();
}
