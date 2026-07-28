part of 'native_browser_platform.dart';

extension _NativeBrowserPlatformEvents on NativeAleraBrowserPlatform {
  void _handleNativeEvent(Map<Object?, Object?> event) {
    final type = event['type'] as String? ?? '';
    if (type.endsWith('Request')) {
      unawaited(
        _handleDecisionRequest(type, event).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          if (!_events.isClosed) {
            _events.addError(error, stackTrace);
          }
        }),
      );
      return;
    }
    final pageId = event['pageId'] as String? ?? '';
    final occurredAt = _timestamp;
    switch (type) {
      case 'navigationStarted':
        final url = Uri.tryParse(event['url'] as String? ?? '');
        if (url != null) {
          _invalidatePage(pageId);
          _updatePage(pageId, url: url);
          _emit(
            AleraBrowserNavigationStarted(
              pageId: pageId,
              occurredAt: occurredAt,
              url: url,
            ),
          );
        }
      case 'navigationCommitted':
        final url = Uri.tryParse(event['url'] as String? ?? '');
        if (url != null) {
          _updatePage(pageId, url: url);
          _emit(
            AleraBrowserNavigationCommitted(
              pageId: pageId,
              occurredAt: occurredAt,
              url: url,
            ),
          );
        }
      case 'navigationFinished':
        final url = Uri.tryParse(event['url'] as String? ?? '');
        final rawTitle = event['title'] as String?;
        final title = rawTitle == null
            ? null
            : normalizeAleraBrowserTitle(rawTitle);
        if (url != null) {
          _updatePage(pageId, url: url, title: title);
          _emit(
            AleraBrowserNavigationFinished(
              pageId: pageId,
              occurredAt: occurredAt,
              url: url,
              title: title,
              canGoBack: event['canGoBack'] as bool?,
              canGoForward: event['canGoForward'] as bool?,
            ),
          );
        }
      case 'urlChanged':
        final url = Uri.tryParse(event['url'] as String? ?? '');
        if (url != null) {
          _updatePage(pageId, url: url);
          _emit(
            AleraBrowserUrlChanged(
              pageId: pageId,
              occurredAt: occurredAt,
              url: url,
            ),
          );
        }
      case 'progress':
        _emit(
          AleraBrowserProgressChanged(
            pageId: pageId,
            occurredAt: occurredAt,
            progress: (event['progress'] as num?)?.toDouble() ?? 0,
          ),
        );
      case 'loadFailed':
        _emit(
          AleraBrowserLoadFailed(
            pageId: pageId,
            occurredAt: occurredAt,
            url: Uri.tryParse(event['url'] as String? ?? ''),
            description: event['description'] as String? ?? 'Load failed.',
          ),
        );
      case 'pageClosed':
        _automation.invalidate(pageId);
        _pages.remove(pageId);
        _emit(AleraBrowserPageClosed(pageId: pageId, occurredAt: occurredAt));
      case 'console':
        _emit(
          AleraBrowserConsoleMessage(
            pageId: pageId,
            occurredAt: occurredAt,
            level: _decodeConsoleLevel(event['level'] as String?),
            message: event['message'] as String? ?? '',
          ),
        );
      case 'downloadChanged':
        _emit(
          AleraBrowserDownloadChanged(
            pageId: pageId,
            occurredAt: occurredAt,
            downloadId: event['downloadId'] as String? ?? '',
            state: _decodeDownloadState(event['state'] as String?),
            receivedBytes: (event['receivedBytes'] as num?)?.toInt() ?? 0,
            totalBytes: (event['totalBytes'] as num?)?.toInt(),
            suggestedFileName: event['suggestedFileName'] as String?,
            destinationPath: event['destinationPath'] as String?,
            errorCode: event['errorCode'] as String?,
          ),
        );
    }
  }

  Future<void> _handleDecisionRequest(
    String type,
    Map<Object?, Object?> event,
  ) async {
    final decisionId = event['decisionId'] as String? ?? '';
    final pageId = event['pageId'] as String? ?? '';
    switch (type) {
      case 'permissionRequest':
        final decision =
            await callbacks.onPermissionRequest?.call(
              AleraBrowserPermissionRequest(
                pageId: pageId,
                origin: Uri.tryParse(event['origin'] as String? ?? ''),
                resources:
                    (event['resources'] as List<Object?>? ?? const <Object?>[])
                        .whereType<String>()
                        .toSet(),
              ),
            ) ??
            AleraBrowserPermissionDecision.deny;
        await _resolveDecision(decisionId, decision.name);
      case 'tlsRequest':
        final decision =
            await callbacks.onTlsError?.call(
              AleraBrowserTlsError(
                pageId: pageId,
                url: Uri.tryParse(event['url'] as String? ?? ''),
                description: event['description'] as String?,
              ),
            ) ??
            AleraBrowserTlsDecision.cancel;
        await _resolveDecision(decisionId, decision.name);
      case 'popupRequest':
        await _handlePopupDecision(decisionId, pageId, event);
      case 'downloadRequest':
        await _handleDownloadDecision(decisionId, pageId, event);
    }
  }

  Future<void> _handlePopupDecision(
    String decisionId,
    String pageId,
    Map<Object?, Object?> event,
  ) async {
    final url = Uri.tryParse(event['url'] as String? ?? '');
    final transientPageId = event['transientPageId'] as String? ?? '';
    if (transientPageId.isNotEmpty && !_pages.containsKey(transientPageId)) {
      _pages[transientPageId] = _NativePage(
        AleraBrowserPage(
          id: transientPageId,
          profileId: event['profileId'] as String? ?? 'default',
          url: url,
          isAttached: false,
          openerPageId: pageId,
          transient: true,
        ),
      );
    }
    final webScheme =
        url != null &&
        (url.scheme == 'http' ||
            url.scheme == 'https' ||
            url.toString() == 'about:blank');
    final decision = webScheme
        ? await callbacks.onPopupRequest?.call(
                AleraBrowserPopupRequest(
                  requestId: decisionId,
                  pageId: pageId,
                  transientPageId: transientPageId,
                  url: url,
                  windowName: event['windowName'] as String?,
                  userInitiated: event['userInitiated'] as bool? ?? false,
                  trusted: event['trusted'] as bool? ?? false,
                  requiresOpener: event['requiresOpener'] as bool? ?? false,
                ),
              ) ??
              const AleraBrowserPopupDecision.deny()
        : const AleraBrowserPopupDecision.deny();
    await _resolveDecision(
      decisionId,
      decision.disposition.name,
      targetPageId: decision.targetPageId,
    );
    if (decision.disposition == AleraBrowserPopupDisposition.deny) {
      _pages.remove(transientPageId);
    }
  }

  Future<void> _handleDownloadDecision(
    String decisionId,
    String pageId,
    Map<Object?, Object?> event,
  ) async {
    final downloadId = event['downloadId'] as String? ?? decisionId;
    final totalBytes = (event['totalBytes'] as num?)?.toInt();
    _emit(
      AleraBrowserDownloadChanged(
        pageId: pageId,
        occurredAt: _timestamp,
        downloadId: downloadId,
        state: AleraBrowserDownloadState.requested,
        receivedBytes: 0,
        totalBytes: totalBytes,
        suggestedFileName: event['suggestedFileName'] as String?,
      ),
    );
    final rawUrl = event['url'] as String? ?? '';
    final url = Uri.tryParse(rawUrl);
    final decision = url == null
        ? const AleraBrowserDownloadDecision.deny()
        : await callbacks.onDownloadRequest?.call(
                AleraBrowserDownloadRequest(
                  pageId: pageId,
                  url: url,
                  suggestedFileName: event['suggestedFileName'] as String?,
                  mimeType: event['mimeType'] as String?,
                  totalBytes: totalBytes,
                ),
              ) ??
              const AleraBrowserDownloadDecision.deny();
    await _resolveDecision(
      decisionId,
      decision.disposition.name,
      destinationPath: decision.destinationPath,
    );
  }

  Future<void> _resolveDecision(
    String decisionId,
    String decision, {
    String? targetPageId,
    String? destinationPath,
  }) => _channel.invokeVoid('decision.resolve', <String, Object?>{
    'decisionId': decisionId,
    'decision': decision,
    'targetPageId': targetPageId,
    'destinationPath': destinationPath,
  });

  void _invalidatePage(String pageId) {
    final page = _pages[pageId];
    if (page == null) {
      return;
    }
    page.generation += 1;
    _automation.invalidate(pageId);
  }

  void _updatePage(String pageId, {Uri? url, String? title}) {
    final page = _pages[pageId];
    if (page != null) {
      page.model = _copyPage(page.model, url: url, title: title);
    }
  }

  AleraBrowserConsoleLevel _decodeConsoleLevel(String? value) =>
      switch (value) {
        'debug' => AleraBrowserConsoleLevel.debug,
        'info' => AleraBrowserConsoleLevel.info,
        'warning' => AleraBrowserConsoleLevel.warning,
        'error' => AleraBrowserConsoleLevel.error,
        _ => AleraBrowserConsoleLevel.unknown,
      };

  AleraBrowserDownloadState _decodeDownloadState(String? value) =>
      switch (value) {
        'requested' => AleraBrowserDownloadState.requested,
        'inProgress' => AleraBrowserDownloadState.inProgress,
        'completed' => AleraBrowserDownloadState.completed,
        'cancelled' => AleraBrowserDownloadState.cancelled,
        _ => AleraBrowserDownloadState.failed,
      };

  DateTime get _timestamp => _now().toUtc();

  void _emit(AleraBrowserEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }
}
