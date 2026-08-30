enum AleraBrowserEngine { wkWebView, webView2, webKitGtk, unavailable }

enum AleraBrowserTlsTrustScope { none, page, profileSession }

/// Runtime facts used to gate every browser operation.
final class const AleraBrowserCapabilities({
  required final AleraBrowserEngine engine,
  required final bool engineAvailable,
  required final bool pageSurface,
  required final bool isolatedProfiles,
  required final bool ephemeralProfiles,
  required final bool deterministicPageClose,
  required final bool navigation,
  required final bool navigationEvents,
  required final bool javascript,
  required final bool basicCookies,
  required final bool fullCookies,
  required final bool permissionCallbacks,
  required final bool tlsCallbacks,
  final AleraBrowserTlsTrustScope tlsTrustScope =
      AleraBrowserTlsTrustScope.none,
  required final bool popupCallbacks,
  required final bool downloadCallbacks,
  required final bool domSnapshot,
  required final bool domActions,
  required final bool crossOriginFrameAutomation,
  required final bool nativeFileUpload,
  required final bool trustedInputEvents,
  required final bool viewportScreenshot,
  required final bool fullPageScreenshot,
  required final bool pdf,
  required final bool flutterOverlayOcclusion,
  required final bool atomicCookieImport,
  required final bool manualJsonCookieImport,
  final String? engineVersion,
  final bool? linuxGtkOverlay,
  final Set<String> nativeCookieImportSources = const <String>{},
  final Set<String> requiredNativeCookieImportSources = const <String>{},
  final List<String> limitations = const <String>[],
}) {
  const new unavailable({required List<String> limitations})
    : this(
        engine: .unavailable,
        engineAvailable: false,
        pageSurface: false,
        isolatedProfiles: false,
        ephemeralProfiles: false,
        deterministicPageClose: false,
        navigation: false,
        navigationEvents: false,
        javascript: false,
        basicCookies: false,
        fullCookies: false,
        permissionCallbacks: false,
        tlsCallbacks: false,
        popupCallbacks: false,
        downloadCallbacks: false,
        domSnapshot: false,
        domActions: false,
        crossOriginFrameAutomation: false,
        nativeFileUpload: false,
        trustedInputEvents: false,
        viewportScreenshot: false,
        fullPageScreenshot: false,
        pdf: false,
        flutterOverlayOcclusion: false,
        atomicCookieImport: false,
        manualJsonCookieImport: false,
        limitations: limitations,
      );

  Set<String> get platformRequiredNativeCookieImportSources => switch (engine) {
    AleraBrowserEngine.wkWebView => const <String>{
      'chrome',
      'edge',
      'arc',
      'brave',
      'comet',
      'helium',
      'firefox',
      'safari',
    },
    AleraBrowserEngine.webView2 => const <String>{
      'chrome',
      'edge',
      'brave',
      'comet',
      'firefox',
    },
    AleraBrowserEngine.webKitGtk => const <String>{
      'chrome',
      'edge',
      'brave',
      'firefox',
    },
    AleraBrowserEngine.unavailable => const <String>{},
  };

  bool get meetsBrowserTabGate =>
      engineAvailable &&
      pageSurface &&
      isolatedProfiles &&
      ephemeralProfiles &&
      deterministicPageClose &&
      navigation &&
      navigationEvents &&
      javascript &&
      fullCookies &&
      permissionCallbacks &&
      tlsCallbacks &&
      tlsTrustScope != AleraBrowserTlsTrustScope.none &&
      popupCallbacks &&
      downloadCallbacks &&
      domSnapshot &&
      domActions &&
      viewportScreenshot &&
      fullPageScreenshot &&
      pdf &&
      flutterOverlayOcclusion &&
      (engine != AleraBrowserEngine.webKitGtk || linuxGtkOverlay == true);

  bool get meetsCookieImportGate =>
      isolatedProfiles &&
      fullCookies &&
      atomicCookieImport &&
      manualJsonCookieImport;

  bool get meetsStableGate =>
      meetsBrowserTabGate &&
      meetsCookieImportGate &&
      nativeCookieImportSources.containsAll(
        platformRequiredNativeCookieImportSources,
      );
}
