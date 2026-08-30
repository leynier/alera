import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:alera/src/features/browser/domain/browser_engine_event.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_page_state.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';

BrowserPageState reduceBrowserPageEvent(
  BrowserPageState state,
  BrowserEngineEvent event,
) {
  return switch (event) {
    BrowserNavigationStarted value => state.copyWith(
      url: value.url,
      loadPhase: .started,
      loadProgress: 0,
      security: browserSecurityForUrl(value.url, committed: false),
      clearError: true,
      updatedAt: value.occurredAt,
    ),
    BrowserNavigationCommitted value => state.copyWith(
      url: value.url,
      loadPhase: .committed,
      security: browserSecurityForUrl(value.url, committed: true),
      updatedAt: value.occurredAt,
    ),
    BrowserNavigationFinished value => state.copyWith(
      url: value.url,
      title: value.title,
      loadPhase: .finished,
      clearLoadProgress: true,
      clearError: true,
      canGoBack: value.canGoBack,
      canGoForward: value.canGoForward,
      security: browserSecurityForUrl(value.url, committed: true),
      updatedAt: value.occurredAt,
    ),
    BrowserUrlChanged value => state.copyWith(
      url: value.url,
      updatedAt: value.occurredAt,
    ),
    BrowserProgressChanged value when state.isLoading => state.copyWith(
      loadProgress: value.progress.clamp(0.0, 1.0),
      updatedAt: value.occurredAt,
    ),
    BrowserProgressChanged() => state,
    BrowserLoadFailed value => state.copyWith(
      url: value.url,
      loadPhase: .failed,
      clearLoadProgress: true,
      error: value.failure,
      security:
          (value.failure.code == BrowserErrorCode.certificateRejected ||
              _isCertificateFailure(value.failure.message))
          ? BrowserSecurityState(
              level: .certificateFailure,
              origin: value.url == null ? null : browserOrigin(value.url!),
            )
          : state.security,
      updatedAt: value.occurredAt,
    ),
    BrowserSecurityChanged value => state.copyWith(
      security: value.security,
      updatedAt: value.occurredAt,
    ),
    BrowserDownloadChanged value => state.copyWith(
      downloads: _replaceDownload(state.downloads, value.download),
      updatedAt: value.occurredAt,
    ),
    BrowserPermissionRequested() ||
    BrowserPopupRequested() ||
    BrowserPageClosed() ||
    BrowserConsoleMessage() => state,
  };
}

bool _isCertificateFailure(String message) {
  final normalized = message.toLowerCase();
  return normalized.contains('certificate') ||
      normalized.contains('cert error') ||
      normalized.contains('tls');
}

List<BrowserDownload> _replaceDownload(
  List<BrowserDownload> downloads,
  BrowserDownload next,
) {
  BrowserDownload? existing;
  for (final download in downloads) {
    if (download.id == next.id) {
      existing = download;
      break;
    }
  }
  final replacement = existing == null
      ? next
      : BrowserDownload(
          id: next.id,
          pageId: next.pageId,
          fileName: next.fileName == next.id
              ? existing.fileName
              : next.fileName,
          status: next.status,
          receivedBytes: next.receivedBytes,
          totalBytes: next.totalBytes ?? existing.totalBytes,
          savePath: next.savePath ?? existing.savePath,
          error: next.error,
          startedAt: existing.startedAt,
        );
  final values = <BrowserDownload>[
    for (final download in downloads)
      if (download.id == replacement.id) ...<BrowserDownload>[
        replacement,
      ] else ...<BrowserDownload>[download],
  ];
  if (existing == null) {
    values.add(replacement);
  }
  return List<BrowserDownload>.unmodifiableOf(values);
}
