import 'package:alera/src/features/browser/domain/browser_automation.dart';
import 'package:alera/src/features/browser/domain/browser_cookie.dart';
import 'package:alera/src/features/browser/domain/browser_cookie_import.dart';
import 'package:alera/src/features/browser/domain/browser_engine_event.dart';
import 'package:alera/src/features/browser/domain/browser_engine_models.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';

abstract interface class BrowserEngine {
  Stream<BrowserEngineEvent> get events;

  Future<BrowserEngineCapabilities> probeCapabilities();

  Future<List<BrowserProfile>> listProfiles();

  Future<BrowserProfile> createProfile({
    required String id,
    required String label,
    required BrowserProfileKind kind,
    required bool persistent,
  });

  Future<void> deleteProfile(String profileId);

  BrowserCookieImportGesture beginCookieImportGesture();

  Future<List<BrowserCookieImportSourceStatus>> probeCookieImportSources(
    BrowserCookieImportGesture gesture,
  );

  Future<BrowserCookieImportResult> importCookies({
    required BrowserCookieImportGesture gesture,
    required String profileId,
    required BrowserImportSourceFamily source,
    String? sourceProfileName,
    String? manualJson,
  });

  Future<void> createPage(
    BrowserPage page, {
    String? openerPageId,
    bool transient = false,
  });

  Future<void> adoptTransientPage(BrowserPage page);

  Future<void> promoteTransientPage(String pageId);

  Future<void> attachPage(String pageId);

  Future<void> detachPage(String pageId);

  Future<void> setPageObscured(String pageId, {required bool obscured});

  Future<void> closePage(String pageId);

  Future<void> loadUrl(String pageId, Uri url);

  Future<void> back(String pageId);

  Future<void> forward(String pageId);

  Future<void> reload(String pageId);

  Future<void> stop(String pageId);

  Future<Object?> evaluateJavaScript(String pageId, String expression);

  Future<List<BrowserCookie>> getCookies(String pageId, {Uri? url});

  Future<void> setCookie(String pageId, BrowserCookie cookie);

  Future<void> deleteCookies(
    String pageId, {
    String? name,
    Uri? url,
    String? domain,
    String? path,
  });

  Future<BrowserAutomationSnapshot> snapshot(
    String pageId, {
    bool interactiveOnly = false,
    int maxNodes = 500,
  });

  Future<void> performAction(String pageId, BrowserAutomationAction action);

  Future<BrowserArtifactResult> captureScreenshot(
    String pageId, {
    required String destinationPath,
    required DateTime expiresAt,
    bool fullPage = false,
  });

  Future<BrowserArtifactResult> printToPdf(
    String pageId, {
    required String destinationPath,
    required DateTime expiresAt,
  });

  Future<void> answerPermission(
    BrowserPermissionRequest request,
    BrowserPermissionDecision decision,
  );

  Future<void> answerCertificateChallenge(
    String challengeId, {
    required bool proceed,
  });

  Future<void> answerPopup(String requestId, {required bool allow});
}
