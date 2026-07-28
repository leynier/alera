import 'package:alera_browser/alera_browser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stable gate requires browser and every platform import source', () {
    final ready = _capabilities(
      nativeSources: const <String>{'chrome', 'edge', 'brave', 'firefox'},
      requiredSources: const <String>{'chrome'},
    );
    final missingSource = _capabilities(
      nativeSources: const <String>{'chrome', 'edge', 'brave'},
      requiredSources: const <String>{'chrome'},
    );

    expect(ready.meetsBrowserTabGate, isTrue);
    expect(ready.meetsCookieImportGate, isTrue);
    expect(ready.meetsStableGate, isTrue);
    expect(missingSource.meetsStableGate, isFalse);
  });

  test('WebKitGTK stable gate requires the runner overlay', () {
    final missingOverlay = _capabilities(
      nativeSources: const <String>{'chrome', 'edge', 'brave', 'firefox'},
      requiredSources: const <String>{},
      linuxGtkOverlay: false,
    );

    expect(missingOverlay.meetsBrowserTabGate, isFalse);
    expect(missingOverlay.meetsStableGate, isFalse);
  });
}

AleraBrowserCapabilities _capabilities({
  required Set<String> nativeSources,
  required Set<String> requiredSources,
  bool linuxGtkOverlay = true,
}) => AleraBrowserCapabilities(
  engine: AleraBrowserEngine.webKitGtk,
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
  crossOriginFrameAutomation: false,
  nativeFileUpload: true,
  trustedInputEvents: false,
  viewportScreenshot: true,
  fullPageScreenshot: true,
  pdf: true,
  flutterOverlayOcclusion: true,
  atomicCookieImport: true,
  manualJsonCookieImport: true,
  linuxGtkOverlay: linuxGtkOverlay,
  nativeCookieImportSources: nativeSources,
  requiredNativeCookieImportSources: requiredSources,
  limitations: const <String>['trusted_input_events_unavailable'],
);
