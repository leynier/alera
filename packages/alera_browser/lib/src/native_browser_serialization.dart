import 'browser_capabilities.dart';
import 'browser_cookie_import.dart';
import 'browser_models.dart';

AleraBrowserCapabilities decodeNativeBrowserCapabilities(
  Map<Object?, Object?> value,
) {
  final engine = switch (value['engine']) {
    'wkWebView' => AleraBrowserEngine.wkWebView,
    'webView2' => AleraBrowserEngine.webView2,
    'webKitGtk' => AleraBrowserEngine.webKitGtk,
    _ => AleraBrowserEngine.unavailable,
  };
  final limitations =
      (value['limitations'] as List<Object?>? ?? const <Object?>[])
          .whereType<String>()
          .toList(growable: false);
  final nativeSources =
      (value['nativeCookieImportSources'] as List<Object?>? ??
              const <Object?>[])
          .whereType<String>()
          .toSet();
  final requiredSources =
      (value['requiredNativeCookieImportSources'] as List<Object?>? ??
              const <Object?>[])
          .whereType<String>()
          .toSet();
  bool flag(String key) => value[key] as bool? ?? false;
  return AleraBrowserCapabilities(
    engine: engine,
    engineVersion: value['engineVersion'] as String?,
    engineAvailable: flag('engineAvailable'),
    pageSurface: flag('pageSurface'),
    isolatedProfiles: flag('isolatedProfiles'),
    ephemeralProfiles: flag('ephemeralProfiles'),
    deterministicPageClose: flag('deterministicPageClose'),
    navigation: flag('navigation'),
    navigationEvents: flag('navigationEvents'),
    javascript: flag('javascript'),
    basicCookies: flag('basicCookies'),
    fullCookies: flag('fullCookies'),
    permissionCallbacks: flag('permissionCallbacks'),
    tlsCallbacks: flag('tlsCallbacks'),
    tlsTrustScope: switch (value['tlsTrustScope']) {
      'page' => AleraBrowserTlsTrustScope.page,
      'profileSession' => AleraBrowserTlsTrustScope.profileSession,
      _ => AleraBrowserTlsTrustScope.none,
    },
    popupCallbacks: flag('popupCallbacks'),
    downloadCallbacks: flag('downloadCallbacks'),
    domSnapshot: flag('domSnapshot'),
    domActions: flag('domActions'),
    crossOriginFrameAutomation: flag('crossOriginFrameAutomation'),
    nativeFileUpload: flag('nativeFileUpload'),
    trustedInputEvents: flag('trustedInputEvents'),
    viewportScreenshot: flag('viewportScreenshot'),
    fullPageScreenshot: flag('fullPageScreenshot'),
    pdf: flag('pdf'),
    flutterOverlayOcclusion: flag('flutterOverlayOcclusion'),
    atomicCookieImport: flag('atomicCookieImport'),
    manualJsonCookieImport: flag('manualJsonCookieImport'),
    linuxGtkOverlay: value['linuxGtkOverlay'] as bool?,
    nativeCookieImportSources: nativeSources,
    requiredNativeCookieImportSources: requiredSources,
    limitations: limitations,
  );
}

AleraBrowserProfile decodeNativeBrowserProfile(Map<Object?, Object?> value) =>
    AleraBrowserProfile(
      id: value['id'] as String? ?? '',
      storage: value['storage'] == 'ephemeral'
          ? AleraBrowserProfileStorage.ephemeral
          : AleraBrowserProfileStorage.persistent,
      isDefault: value['isDefault'] as bool? ?? false,
    );

Map<String, Object?> encodeNativeBrowserCookie(AleraBrowserCookie cookie) =>
    <String, Object?>{
      'name': cookie.name,
      'value': cookie.value,
      'domain': cookie.domain,
      'path': cookie.path,
      'expiresUtc': cookie.expiresUtc?.millisecondsSinceEpoch,
      'secure': cookie.secure,
      'httpOnly': cookie.httpOnly,
      'sameSite': cookie.sameSite?.name,
      'session': cookie.session,
    };

AleraBrowserCookie decodeNativeBrowserCookie(Map<Object?, Object?> value) =>
    AleraBrowserCookie(
      name: value['name'] as String? ?? '',
      value: value['value'] as String? ?? '',
      domain: value['domain'] as String? ?? '',
      path: value['path'] as String? ?? '/',
      expiresUtc: switch (value['expiresUtc']) {
        final int milliseconds => DateTime.fromMillisecondsSinceEpoch(
          milliseconds,
          isUtc: true,
        ),
        _ => null,
      },
      secure: value['secure'] as bool? ?? false,
      httpOnly: value['httpOnly'] as bool? ?? false,
      sameSite: switch (value['sameSite']) {
        'none' => AleraBrowserCookieSameSite.none,
        'lax' => AleraBrowserCookieSameSite.lax,
        'strict' => AleraBrowserCookieSameSite.strict,
        _ => null,
      },
      session: value['session'] as bool?,
    );

AleraBrowserArtifact decodeNativeBrowserArtifact(Map<Object?, Object?> value) =>
    AleraBrowserArtifact(
      path: value['path'] as String? ?? '',
      mimeType: value['mimeType'] as String? ?? 'application/octet-stream',
      sizeBytes: (value['sizeBytes'] as num?)?.toInt() ?? 0,
      width: (value['width'] as num?)?.toInt(),
      height: (value['height'] as num?)?.toInt(),
      suggestedFileName: value['suggestedFileName'] as String?,
    );

AleraBrowserCookieImportSource decodeCookieImportSource(String id) =>
    AleraBrowserCookieImportSource.values.firstWhere(
      (source) => source.id == id,
    );
