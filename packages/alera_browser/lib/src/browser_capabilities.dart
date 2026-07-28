enum AleraBrowserEngine { wkWebView, webView2, webKitGtk, unavailable }

enum AleraBrowserTlsTrustScope { none, page, profileSession }

/// Runtime facts used to gate every browser operation.
final class AleraBrowserCapabilities {
  const AleraBrowserCapabilities({
    required this.engine,
    required this.engineAvailable,
    required this.pageSurface,
    required this.isolatedProfiles,
    required this.ephemeralProfiles,
    required this.deterministicPageClose,
    required this.navigation,
    required this.navigationEvents,
    required this.javascript,
    required this.basicCookies,
    required this.fullCookies,
    required this.permissionCallbacks,
    required this.tlsCallbacks,
    this.tlsTrustScope = AleraBrowserTlsTrustScope.none,
    required this.popupCallbacks,
    required this.downloadCallbacks,
    required this.domSnapshot,
    required this.domActions,
    required this.crossOriginFrameAutomation,
    required this.nativeFileUpload,
    required this.trustedInputEvents,
    required this.viewportScreenshot,
    required this.fullPageScreenshot,
    required this.pdf,
    required this.flutterOverlayOcclusion,
    required this.atomicCookieImport,
    required this.manualJsonCookieImport,
    this.engineVersion,
    this.linuxGtkOverlay,
    this.nativeCookieImportSources = const <String>{},
    this.requiredNativeCookieImportSources = const <String>{},
    this.limitations = const <String>[],
  });

  const AleraBrowserCapabilities.unavailable({
    required List<String> limitations,
  }) : this(
         engine: AleraBrowserEngine.unavailable,
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

  final AleraBrowserEngine engine;
  final String? engineVersion;
  final bool engineAvailable;
  final bool pageSurface;
  final bool isolatedProfiles;
  final bool ephemeralProfiles;
  final bool deterministicPageClose;
  final bool navigation;
  final bool navigationEvents;
  final bool javascript;
  final bool basicCookies;
  final bool fullCookies;
  final bool permissionCallbacks;
  final bool tlsCallbacks;
  final AleraBrowserTlsTrustScope tlsTrustScope;
  final bool popupCallbacks;
  final bool downloadCallbacks;
  final bool domSnapshot;
  final bool domActions;
  final bool crossOriginFrameAutomation;
  final bool nativeFileUpload;
  final bool trustedInputEvents;
  final bool viewportScreenshot;
  final bool fullPageScreenshot;
  final bool pdf;
  final bool flutterOverlayOcclusion;
  final bool atomicCookieImport;
  final bool manualJsonCookieImport;
  final bool? linuxGtkOverlay;
  final Set<String> nativeCookieImportSources;
  final Set<String> requiredNativeCookieImportSources;
  final List<String> limitations;

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
