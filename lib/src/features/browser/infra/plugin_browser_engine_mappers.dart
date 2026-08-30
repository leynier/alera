part of 'plugin_browser_engine.dart';

BrowserFailure _failureFromPlugin(AleraBrowserException error) {
  final code = switch (error.code) {
    'stale_element' ||
    'stale_target' => BrowserErrorCode.staleAutomationReference,
    'wrong_element_type' ||
    'invalid_snapshot' => BrowserErrorCode.invalidPayload,
    'wait_timeout' => BrowserErrorCode.timeout,
    'page_not_found' => BrowserErrorCode.pageNotFound,
    _ when error is AleraBrowserUnsupportedError =>
      BrowserErrorCode.unsupportedCapability,
    _ => BrowserErrorCode.unknown,
  };
  return BrowserFailure(
    code: code,
    message: error.message,
    recoverable:
        code == BrowserErrorCode.staleAutomationReference ||
        code == BrowserErrorCode.timeout ||
        error is! AleraBrowserStateError,
    details: <String, Object?>{'pluginCode': error.code},
  );
}

BrowserEngineEvent? _eventFromPlugin(AleraBrowserEvent event) {
  return switch (event) {
    AleraBrowserNavigationStarted value => BrowserNavigationStarted(
      pageId: value.pageId,
      occurredAt: value.occurredAt,
      url: value.url,
    ),
    AleraBrowserNavigationCommitted value => BrowserNavigationCommitted(
      pageId: value.pageId,
      occurredAt: value.occurredAt,
      url: value.url,
    ),
    AleraBrowserNavigationFinished value => BrowserNavigationFinished(
      pageId: value.pageId,
      occurredAt: value.occurredAt,
      url: value.url,
      title: normalizeAleraBrowserTitle(value.title ?? ''),
      canGoBack: value.canGoBack,
      canGoForward: value.canGoForward,
    ),
    AleraBrowserUrlChanged value => BrowserUrlChanged(
      pageId: value.pageId,
      occurredAt: value.occurredAt,
      url: value.url,
    ),
    AleraBrowserProgressChanged value => BrowserProgressChanged(
      pageId: value.pageId,
      occurredAt: value.occurredAt,
      progress: value.progress,
    ),
    AleraBrowserLoadFailed value => BrowserLoadFailed(
      pageId: value.pageId,
      occurredAt: value.occurredAt,
      url: value.url,
      failure: BrowserFailure(
        code: .unknown,
        message: value.description,
        recoverable: true,
      ),
    ),
    AleraBrowserConsoleMessage value => BrowserConsoleMessage(
      pageId: value.pageId,
      occurredAt: value.occurredAt,
      level: _consoleLevelFromPlugin(value.level),
      message: value.message,
    ),
    AleraBrowserDownloadChanged value => BrowserDownloadChanged(
      pageId: value.pageId,
      occurredAt: value.occurredAt,
      download: BrowserDownload(
        id: value.downloadId,
        pageId: value.pageId,
        fileName: value.suggestedFileName ?? value.downloadId,
        status: _downloadStatusFromPlugin(value.state),
        receivedBytes: value.receivedBytes,
        totalBytes: value.totalBytes,
        savePath: value.destinationPath,
        error: value.errorCode,
        startedAt: value.occurredAt,
      ),
    ),
    AleraBrowserPopupBlocked() => null,
    AleraBrowserPageClosed value => BrowserPageClosed(
      pageId: value.pageId,
      occurredAt: value.occurredAt,
    ),
  };
}

AleraBrowserCookie _cookieToPlugin(BrowserCookie value) {
  return AleraBrowserCookie(
    name: value.name,
    value: value.value,
    domain: value.domain,
    path: value.path,
    secure: value.secure,
    httpOnly: value.httpOnly,
    expiresUtc: value.expiresAt,
    sameSite: switch (value.sameSite) {
      BrowserCookieSameSite.none => AleraBrowserCookieSameSite.none,
      BrowserCookieSameSite.lax => AleraBrowserCookieSameSite.lax,
      BrowserCookieSameSite.strict => AleraBrowserCookieSameSite.strict,
      BrowserCookieSameSite.unspecified => null,
    },
  );
}

BrowserCookie _cookieFromPlugin(AleraBrowserCookie value) {
  return BrowserCookie(
    name: value.name,
    value: value.value,
    domain: value.domain,
    path: value.path,
    secure: value.secure,
    httpOnly: value.httpOnly,
    expiresAt: value.expiresUtc,
    sameSite: switch (value.sameSite) {
      AleraBrowserCookieSameSite.none => BrowserCookieSameSite.none,
      AleraBrowserCookieSameSite.lax => BrowserCookieSameSite.lax,
      AleraBrowserCookieSameSite.strict => BrowserCookieSameSite.strict,
      null => BrowserCookieSameSite.unspecified,
    },
  );
}

AleraBrowserActionKind _actionKindToPlugin(BrowserAutomationActionKind value) {
  return switch (value) {
    BrowserAutomationActionKind.click => AleraBrowserActionKind.click,
    BrowserAutomationActionKind.fill => AleraBrowserActionKind.fill,
    BrowserAutomationActionKind.type => AleraBrowserActionKind.type,
    BrowserAutomationActionKind.select => AleraBrowserActionKind.select,
    BrowserAutomationActionKind.check => AleraBrowserActionKind.check,
    BrowserAutomationActionKind.uncheck => AleraBrowserActionKind.uncheck,
    BrowserAutomationActionKind.focus => AleraBrowserActionKind.focus,
    BrowserAutomationActionKind.clear => AleraBrowserActionKind.clear,
    BrowserAutomationActionKind.hover => AleraBrowserActionKind.hover,
    BrowserAutomationActionKind.drag => AleraBrowserActionKind.drag,
    BrowserAutomationActionKind.keypress => AleraBrowserActionKind.keyPress,
    BrowserAutomationActionKind.scroll => AleraBrowserActionKind.scrollIntoView,
    BrowserAutomationActionKind.upload => AleraBrowserActionKind.upload,
  };
}

List<String> _actionValues(BrowserAutomationAction value) {
  final values = value.options['values'];
  return values is List
      ? <String>[
          for (final item in values)
            if (item is String) item,
        ]
      : const <String>[];
}

List<String> _actionFilePaths(BrowserAutomationAction value) {
  final paths = value.options['filePaths'];
  return paths is List
      ? <String>[
          for (final item in paths)
            if (item is String) item,
        ]
      : const <String>[];
}

BrowserArtifactResult _artifactFromPlugin(
  AleraBrowserArtifact value,
  DateTime expiresAt,
) {
  return BrowserArtifactResult(
    path: value.path,
    mimeType: value.mimeType,
    sizeBytes: value.sizeBytes,
    expiresAt: expiresAt.toUtc(),
    suggestedFileName: value.suggestedFileName,
  );
}

BrowserConsoleLevel _consoleLevelFromPlugin(AleraBrowserConsoleLevel value) {
  return switch (value) {
    AleraBrowserConsoleLevel.debug => BrowserConsoleLevel.debug,
    AleraBrowserConsoleLevel.info => BrowserConsoleLevel.info,
    AleraBrowserConsoleLevel.warning => BrowserConsoleLevel.warning,
    AleraBrowserConsoleLevel.error => BrowserConsoleLevel.error,
    AleraBrowserConsoleLevel.unknown => BrowserConsoleLevel.info,
  };
}

BrowserDownloadStatus _downloadStatusFromPlugin(
  AleraBrowserDownloadState value,
) {
  return switch (value) {
    AleraBrowserDownloadState.requested => BrowserDownloadStatus.pending,
    AleraBrowserDownloadState.inProgress => BrowserDownloadStatus.downloading,
    AleraBrowserDownloadState.completed => BrowserDownloadStatus.completed,
    AleraBrowserDownloadState.cancelled => BrowserDownloadStatus.cancelled,
    AleraBrowserDownloadState.failed => BrowserDownloadStatus.failed,
  };
}

AleraBrowserCookieImportSource _importSourceToPlugin(
  BrowserImportSourceFamily value,
) {
  return switch (value) {
    BrowserImportSourceFamily.chrome => AleraBrowserCookieImportSource.chrome,
    BrowserImportSourceFamily.edge => AleraBrowserCookieImportSource.edge,
    BrowserImportSourceFamily.arc => AleraBrowserCookieImportSource.arc,
    BrowserImportSourceFamily.brave => AleraBrowserCookieImportSource.brave,
    BrowserImportSourceFamily.comet => AleraBrowserCookieImportSource.comet,
    BrowserImportSourceFamily.helium => AleraBrowserCookieImportSource.helium,
    BrowserImportSourceFamily.firefox => AleraBrowserCookieImportSource.firefox,
    BrowserImportSourceFamily.safari => AleraBrowserCookieImportSource.safari,
    BrowserImportSourceFamily.manual =>
      AleraBrowserCookieImportSource.manualJson,
  };
}

BrowserImportSourceFamily _importSourceFromPlugin(
  AleraBrowserCookieImportSource value,
) {
  return switch (value) {
    AleraBrowserCookieImportSource.chrome => BrowserImportSourceFamily.chrome,
    AleraBrowserCookieImportSource.edge => BrowserImportSourceFamily.edge,
    AleraBrowserCookieImportSource.arc => BrowserImportSourceFamily.arc,
    AleraBrowserCookieImportSource.brave => BrowserImportSourceFamily.brave,
    AleraBrowserCookieImportSource.comet => BrowserImportSourceFamily.comet,
    AleraBrowserCookieImportSource.helium => BrowserImportSourceFamily.helium,
    AleraBrowserCookieImportSource.firefox => BrowserImportSourceFamily.firefox,
    AleraBrowserCookieImportSource.safari => BrowserImportSourceFamily.safari,
    AleraBrowserCookieImportSource.manualJson =>
      BrowserImportSourceFamily.manual,
  };
}
