import 'package:alera/src/features/browser/domain/browser_engine_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capability gates require the complete platform contract', () {
    final macCapabilities = BrowserEngineCapabilities(
      engine: 'wkWebView',
      engineAvailable: true,
      pageSurface: true,
      isolatedProfiles: true,
      ephemeralProfiles: true,
      deterministicPageClose: true,
      navigation: true,
      navigationEvents: true,
      javascript: true,
      fullCookies: true,
      permissionCallbacks: true,
      tlsCallbacks: true,
      tlsTrustScope: 'page',
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
      nativeCookieImportSources: const <String>{
        'chrome',
        'edge',
        'arc',
        'brave',
        'comet',
        'helium',
        'firefox',
        'safari',
      },
    );

    expect(macCapabilities.meetsBrowserTabGate, isTrue);
    expect(macCapabilities.meetsCookieImportGate, isTrue);
    expect(macCapabilities.meetsStableGate, isTrue);
    expect(
      macCapabilities.platformRequiredNativeCookieImportSources,
      containsAll(<String>['arc', 'safari']),
    );
    final unavailableTrust = macCapabilities.withPersistentCertificateTrust(
      false,
    );
    expect(unavailableTrust.persistentCertificateTrust, isFalse);
    expect(unavailableTrust.meetsStableGate, isFalse);
    expect(
      unavailableTrust.limitations,
      contains('certificate_trust_sidecar_unavailable'),
    );
    expect(
      macCapabilities
          .withPersistentCertificateTrust(true)
          .persistentCertificateTrust,
      isTrue,
    );

    final linuxCapabilities = BrowserEngineCapabilities(
      engine: 'webKitGtk',
      engineAvailable: true,
      pageSurface: true,
      isolatedProfiles: true,
      ephemeralProfiles: true,
      deterministicPageClose: true,
      navigation: true,
      navigationEvents: true,
      javascript: true,
      fullCookies: true,
      permissionCallbacks: true,
      tlsCallbacks: true,
      tlsTrustScope: 'profileSession',
      popupCallbacks: true,
      downloadCallbacks: true,
      domSnapshot: true,
      domActions: true,
      viewportScreenshot: true,
      fullPageScreenshot: true,
      pdf: true,
      flutterOverlayOcclusion: true,
      linuxGtkOverlay: false,
    );

    expect(linuxCapabilities.meetsBrowserTabGate, isFalse);
    expect(
      linuxCapabilities.platformRequiredNativeCookieImportSources,
      <String>{'chrome', 'edge', 'brave', 'firefox'},
    );
  });

  test('artifact metadata round-trips with UTC expiry and file name', () {
    final artifact = BrowserArtifactResult.fromJson(<String, Object?>{
      'path': '/tmp/browser-artifact.png',
      'mimeType': 'image/png',
      'sizeBytes': 42.8,
      'expiresAt': '2026-07-27T12:30:00-06:00',
      'suggestedFileName': 'capture.png',
    });

    expect(artifact.path, '/tmp/browser-artifact.png');
    expect(artifact.mimeType, 'image/png');
    expect(artifact.sizeBytes, 42);
    expect(artifact.expiresAt, DateTime.utc(2026, 7, 27, 18, 30));
    expect(artifact.suggestedFileName, 'capture.png');
    expect(artifact.toJson(), <String, Object?>{
      'path': '/tmp/browser-artifact.png',
      'mimeType': 'image/png',
      'sizeBytes': 42,
      'expiresAt': '2026-07-27T18:30:00.000Z',
      'suggestedFileName': 'capture.png',
    });
  });

  test('capability diagnostics use user-facing copy', () {
    expect(
      browserCapabilityLimitationMessage(
        'tab_scoped_tls_exception_unavailable',
      ),
      'Tab-scoped TLS exceptions are unavailable.',
    );
    expect(
      browserCapabilityLimitationMessage('future_capability_unavailable'),
      'A required browser capability is unavailable.',
    );
    expect(browserEngineLabel('webKitGtk'), 'WebKitGTK');
  });
}
