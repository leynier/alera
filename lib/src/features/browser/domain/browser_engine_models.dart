final class BrowserEngineCapabilities {
  const BrowserEngineCapabilities({
    required this.engine,
    required this.engineAvailable,
    this.engineVersion,
    this.pageSurface = false,
    this.isolatedProfiles = false,
    this.ephemeralProfiles = false,
    this.deterministicPageClose = false,
    this.navigation = false,
    this.navigationEvents = false,
    this.javascript = false,
    this.basicCookies = false,
    this.fullCookies = false,
    this.permissionCallbacks = false,
    this.tlsCallbacks = false,
    this.tlsTrustScope = 'none',
    this.persistentCertificateTrust = true,
    this.popupCallbacks = false,
    this.downloadCallbacks = false,
    this.domSnapshot = false,
    this.domActions = false,
    this.viewportScreenshot = false,
    this.fullPageScreenshot = false,
    this.pdf = false,
    this.flutterOverlayOcclusion = false,
    this.atomicCookieImport = false,
    this.manualJsonCookieImport = false,
    this.linuxGtkOverlay = false,
    this.nativeCookieImportSources = const <String>{},
    this.requiredNativeCookieImportSources = const <String>{},
    this.limitations = const <String>[],
  });

  final String engine;
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
  final String tlsTrustScope;
  final bool persistentCertificateTrust;
  final bool popupCallbacks;
  final bool downloadCallbacks;
  final bool domSnapshot;
  final bool domActions;
  final bool viewportScreenshot;
  final bool fullPageScreenshot;
  final bool pdf;
  final bool flutterOverlayOcclusion;
  final bool atomicCookieImport;
  final bool manualJsonCookieImport;
  final bool linuxGtkOverlay;
  final Set<String> nativeCookieImportSources;
  final Set<String> requiredNativeCookieImportSources;
  final List<String> limitations;

  Set<String> get platformRequiredNativeCookieImportSources => switch (engine) {
    'wkWebView' => const <String>{
      'chrome',
      'edge',
      'arc',
      'brave',
      'comet',
      'helium',
      'firefox',
      'safari',
    },
    'webView2' => const <String>{'chrome', 'edge', 'brave', 'comet', 'firefox'},
    'webKitGtk' => const <String>{'chrome', 'edge', 'brave', 'firefox'},
    _ => requiredNativeCookieImportSources,
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
      tlsTrustScope != 'none' &&
      popupCallbacks &&
      downloadCallbacks &&
      domSnapshot &&
      domActions &&
      viewportScreenshot &&
      fullPageScreenshot &&
      pdf &&
      flutterOverlayOcclusion &&
      (engine != 'webKitGtk' || linuxGtkOverlay);

  bool get meetsCookieImportGate =>
      isolatedProfiles &&
      fullCookies &&
      atomicCookieImport &&
      manualJsonCookieImport;

  bool get meetsStableGate =>
      meetsBrowserTabGate &&
      meetsCookieImportGate &&
      persistentCertificateTrust &&
      nativeCookieImportSources.containsAll(
        platformRequiredNativeCookieImportSources,
      );

  BrowserEngineCapabilities withPersistentCertificateTrust(bool available) {
    return BrowserEngineCapabilities(
      engine: engine,
      engineAvailable: engineAvailable,
      engineVersion: engineVersion,
      pageSurface: pageSurface,
      isolatedProfiles: isolatedProfiles,
      ephemeralProfiles: ephemeralProfiles,
      deterministicPageClose: deterministicPageClose,
      navigation: navigation,
      navigationEvents: navigationEvents,
      javascript: javascript,
      basicCookies: basicCookies,
      fullCookies: fullCookies,
      permissionCallbacks: permissionCallbacks,
      tlsCallbacks: tlsCallbacks,
      tlsTrustScope: tlsTrustScope,
      persistentCertificateTrust: available,
      popupCallbacks: popupCallbacks,
      downloadCallbacks: downloadCallbacks,
      domSnapshot: domSnapshot,
      domActions: domActions,
      viewportScreenshot: viewportScreenshot,
      fullPageScreenshot: fullPageScreenshot,
      pdf: pdf,
      flutterOverlayOcclusion: flutterOverlayOcclusion,
      atomicCookieImport: atomicCookieImport,
      manualJsonCookieImport: manualJsonCookieImport,
      linuxGtkOverlay: linuxGtkOverlay,
      nativeCookieImportSources: nativeCookieImportSources,
      requiredNativeCookieImportSources: requiredNativeCookieImportSources,
      limitations: available
          ? limitations
          : <String>[...limitations, 'certificate_trust_sidecar_unavailable'],
    );
  }
}

final class BrowserArtifactResult {
  const BrowserArtifactResult({
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
    required this.expiresAt,
    this.suggestedFileName,
  });

  factory BrowserArtifactResult.fromJson(Map<String, Object?> json) {
    final path = json['path'];
    final mimeType = json['mimeType'];
    final sizeBytes = json['sizeBytes'];
    final expiresAt = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    if (path is! String ||
        path.isEmpty ||
        mimeType is! String ||
        sizeBytes is! num ||
        expiresAt == null) {
      throw const FormatException('Browser Artifact Metadata Is Invalid.');
    }
    return BrowserArtifactResult(
      path: path,
      mimeType: mimeType,
      sizeBytes: sizeBytes.toInt(),
      expiresAt: expiresAt.toUtc(),
      suggestedFileName: json['suggestedFileName'] as String?,
    );
  }

  final String path;
  final String mimeType;
  final int sizeBytes;
  final DateTime expiresAt;
  final String? suggestedFileName;

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (suggestedFileName != null) 'suggestedFileName': suggestedFileName,
  };
}

String browserCapabilityLimitationMessage(String code) {
  return switch (code.trim()) {
    'cross_origin_frames_unavailable' =>
      'Cross-Origin Frame Automation Is Unavailable.',
    'native_file_upload_unavailable' => 'Native File Upload Is Unavailable.',
    'trusted_input_events_unavailable' =>
      'Trusted Input Events Are Unavailable.',
    'popup_opener_requirement_unavailable' =>
      'Popup Opener Preservation Is Unavailable.',
    'screenshot_scale_unavailable' =>
      'Exact Screenshot Scaling Is Unavailable.',
    'chromium_app_bound_cookie_import_unavailable' =>
      'Chromium App-Bound Cookie Import Is Unavailable.',
    'tab_scoped_tls_exception_unavailable' =>
      'Tab-Scoped TLS Exceptions Are Unavailable.',
    'certificate_trust_sidecar_unavailable' =>
      'Restart Alera To Enable Local Certificate Trust.',
    'webview2_evergreen_unavailable' =>
      'The WebView2 Evergreen Runtime Is Unavailable.',
    'macos_14_or_wkwebview_required' =>
      'macOS 14 Or A Newer WKWebView Is Required.',
    'flutter_host_view_unavailable' => 'The Flutter Host View Is Unavailable.',
    _ => 'A Required Browser Capability Is Unavailable.',
  };
}

String browserEngineLabel(String engine) {
  return switch (engine) {
    'wkWebView' => 'WKWebView',
    'webView2' => 'WebView2',
    'webKitGtk' => 'WebKitGTK',
    _ => 'System Browser Engine',
  };
}
