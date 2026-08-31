import 'browser_cookie_import.dart';
import 'browser_models.dart';
import 'native_browser_channel.dart';
import 'native_browser_serialization.dart';

final class const AleraNativeBrowserDataStore(
  final AleraBrowserNativeChannel _channel,
) {
  Future<List<AleraBrowserCookie>> getCookies(String profileId, Uri url) async {
    final values = await _channel.invokeList('cookies.get', <String, Object?>{
      'profileId': profileId,
      'url': url.toString(),
    });
    return values
        .whereType<Map<Object?, Object?>>()
        .map(decodeNativeBrowserCookie)
        .toList(growable: false);
  }

  Future<void> setCookie(String profileId, AleraBrowserCookie cookie) =>
      _channel.invokeVoid('cookies.set', <String, Object?>{
        'profileId': profileId,
        'cookie': encodeNativeBrowserCookie(cookie),
      });

  Future<int> deleteCookies(
    String profileId,
    AleraBrowserCookieFilter filter,
  ) async =>
      await _channel.invoke<int>('cookies.delete', <String, Object?>{
        'profileId': profileId,
        'url': filter.url?.toString(),
        'name': filter.name,
        'domain': filter.domain,
        'path': filter.path,
      }) ??
      0;

  Future<List<AleraBrowserCookieImportSourceStatus>>
  probeCookieImportSources() async {
    final values = await _channel.invokeList('cookieImport.probe');
    return values
        .whereType<Map<Object?, Object?>>()
        .map((value) {
          final sourceId = value['source'] as String? ?? '';
          return AleraBrowserCookieImportSourceStatus(
            source: decodeCookieImportSource(sourceId),
            supported: value['supported'] as bool? ?? false,
            available: value['available'] as bool? ?? false,
            profileNames:
                (value['profileNames'] as List<Object?>? ?? const <Object?>[])
                    .whereType<String>()
                    .toList(growable: false),
            detailCode: value['detailCode'] as String?,
          );
        })
        .toList(growable: false);
  }

  Future<AleraBrowserCookieImportResult> importCookies(
    AleraBrowserCookieImportRequest request,
  ) async {
    final source = request is AleraBrowserNativeCookieImportRequest
        ? request.source
        : AleraBrowserCookieImportSource.manualJson;
    final value = await _channel.invokeMap(
      'cookieImport.run',
      <String, Object?>{
        'profileId': request.profileId,
        'source': source.id,
        if (request is AleraBrowserNativeCookieImportRequest)
          'sourceProfileName': request.sourceProfileName,
        if (request is AleraBrowserManualCookieImportRequest)
          'json': request.json,
      },
    );
    return AleraBrowserCookieImportResult(
      source: source,
      profileId: request.profileId,
      outcome: switch (value['outcome']) {
        'imported' => AleraBrowserCookieImportOutcome.imported,
        'partiallyImported' =>
          AleraBrowserCookieImportOutcome.partiallyImported,
        'unavailable' => AleraBrowserCookieImportOutcome.unavailable,
        'denied' => AleraBrowserCookieImportOutcome.denied,
        'failed' => AleraBrowserCookieImportOutcome.failed,
        _ => AleraBrowserCookieImportOutcome.unsupported,
      },
      importedCount: (value['importedCount'] as num?)?.toInt() ?? 0,
      skippedCount: (value['skippedCount'] as num?)?.toInt() ?? 0,
      detailCode: value['detailCode'] as String?,
    );
  }
}
