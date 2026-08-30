final class const BrowserEngineCapabilities({
  required final String engine,
  required final bool engineAvailable,
  final String? engineVersion,
  final bool pageSurface = false,
  final bool isolatedProfiles = false,
  final bool ephemeralProfiles = false,
  final bool deterministicPageClose = false,
  final bool navigation = false,
  final bool navigationEvents = false,
  final bool javascript = false,
  final bool basicCookies = false,
  final bool fullCookies = false,
  final bool permissionCallbacks = false,
  final bool tlsCallbacks = false,
  final String tlsTrustScope = 'none',
  final bool persistentCertificateTrust = true,
  final bool popupCallbacks = false,
  final bool downloadCallbacks = false,
  final bool domSnapshot = false,
  final bool domActions = false,
  final bool viewportScreenshot = false,
  final bool fullPageScreenshot = false,
  final bool pdf = false,
  final bool flutterOverlayOcclusion = false,
  final bool atomicCookieImport = false,
  final bool manualJsonCookieImport = false,
  final bool linuxGtkOverlay = false,
  final Set<String> nativeCookieImportSources = const <String>{},
  final Set<String> requiredNativeCookieImportSources = const <String>{},
  final List<String> limitations = const <String>[],
}) {
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

final class const BrowserArtifactResult({
  required final String path,
  required final String mimeType,
  required final int sizeBytes,
  required final DateTime expiresAt,
  final String? suggestedFileName,
}) {
  factory fromJson(Map<String, Object?> json) {
    final path = json['path'];
    final mimeType = json['mimeType'];
    final sizeBytes = json['sizeBytes'];
    final expiresAt = DateTime.tryParse(json['expiresAt'] as String? ?? '');
    if (path is! String ||
        path.isEmpty ||
        mimeType is! String ||
        sizeBytes is! num ||
        expiresAt == null) {
      throw const FormatException('Browser artifact metadata is invalid.');
    }
    return BrowserArtifactResult(
      path: path,
      mimeType: mimeType,
      sizeBytes: sizeBytes.toInt(),
      expiresAt: expiresAt.toUtc(),
      suggestedFileName: json['suggestedFileName'] as String?,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'path': path,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'suggestedFileName': ?suggestedFileName,
  };
}

String browserCapabilityLimitationMessage(String code) {
  return switch (code.trim()) {
    'cross_origin_frames_unavailable' =>
      'Cross-origin frame automation is unavailable.',
    'native_file_upload_unavailable' => 'Native file upload is unavailable.',
    'trusted_input_events_unavailable' =>
      'Trusted input events are unavailable.',
    'popup_opener_requirement_unavailable' =>
      'Popup opener preservation is unavailable.',
    'screenshot_scale_unavailable' =>
      'Exact screenshot scaling is unavailable.',
    'chromium_app_bound_cookie_import_unavailable' =>
      'Chromium app-bound cookie import is unavailable.',
    'tab_scoped_tls_exception_unavailable' =>
      'Tab-scoped TLS exceptions are unavailable.',
    'certificate_trust_sidecar_unavailable' =>
      'Restart Alera to enable local certificate trust.',
    'webview2_evergreen_unavailable' =>
      'The WebView2 Evergreen runtime is unavailable.',
    'macos_14_or_wkwebview_required' =>
      'macOS 14 or a newer WKWebView is required.',
    'flutter_host_view_unavailable' => 'The Flutter host view is unavailable.',
    _ => 'A required browser capability is unavailable.',
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
