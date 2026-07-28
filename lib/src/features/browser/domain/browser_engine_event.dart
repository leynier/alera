import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';

sealed class BrowserEngineEvent {
  const BrowserEngineEvent({required this.pageId, required this.occurredAt});

  final String pageId;
  final DateTime occurredAt;
}

final class BrowserNavigationStarted extends BrowserEngineEvent {
  const BrowserNavigationStarted({
    required super.pageId,
    required super.occurredAt,
    required this.url,
  });

  final Uri url;
}

final class BrowserNavigationCommitted extends BrowserEngineEvent {
  const BrowserNavigationCommitted({
    required super.pageId,
    required super.occurredAt,
    required this.url,
  });

  final Uri url;
}

final class BrowserNavigationFinished extends BrowserEngineEvent {
  const BrowserNavigationFinished({
    required super.pageId,
    required super.occurredAt,
    required this.url,
    required this.title,
    this.canGoBack,
    this.canGoForward,
  });

  final Uri url;
  final String title;
  final bool? canGoBack;
  final bool? canGoForward;
}

final class BrowserUrlChanged extends BrowserEngineEvent {
  const BrowserUrlChanged({
    required super.pageId,
    required super.occurredAt,
    required this.url,
  });

  final Uri url;
}

final class BrowserProgressChanged extends BrowserEngineEvent {
  const BrowserProgressChanged({
    required super.pageId,
    required super.occurredAt,
    required this.progress,
  });

  final double progress;
}

final class BrowserLoadFailed extends BrowserEngineEvent {
  const BrowserLoadFailed({
    required super.pageId,
    required super.occurredAt,
    required this.failure,
    this.url,
  });

  final Uri? url;
  final BrowserFailure failure;
}

final class BrowserSecurityChanged extends BrowserEngineEvent {
  const BrowserSecurityChanged({
    required super.pageId,
    required super.occurredAt,
    required this.security,
  });

  final BrowserSecurityState security;
}

final class BrowserDownloadChanged extends BrowserEngineEvent {
  const BrowserDownloadChanged({
    required super.pageId,
    required super.occurredAt,
    required this.download,
  });

  final BrowserDownload download;
}

final class BrowserPermissionRequested extends BrowserEngineEvent {
  const BrowserPermissionRequested({
    required super.pageId,
    required super.occurredAt,
    required this.request,
  });

  final BrowserPermissionRequest request;
}

final class BrowserPopupRequested extends BrowserEngineEvent {
  const BrowserPopupRequested({
    required super.pageId,
    required super.occurredAt,
    required this.requestId,
    required this.url,
    required this.userGesture,
    required this.trusted,
    required this.requiresOpener,
  });

  final String requestId;
  final Uri url;
  final bool userGesture;
  final bool trusted;
  final bool requiresOpener;
}

final class BrowserPageClosed extends BrowserEngineEvent {
  const BrowserPageClosed({required super.pageId, required super.occurredAt});
}

final class BrowserConsoleMessage extends BrowserEngineEvent {
  const BrowserConsoleMessage({
    required super.pageId,
    required super.occurredAt,
    required this.level,
    required this.message,
  });

  final BrowserConsoleLevel level;
  final String message;
}

enum BrowserConsoleLevel { debug, info, warning, error }
