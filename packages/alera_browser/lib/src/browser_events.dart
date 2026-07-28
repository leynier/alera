sealed class AleraBrowserEvent {
  const AleraBrowserEvent({required this.pageId, required this.occurredAt});

  final String pageId;
  final DateTime occurredAt;
}

final class AleraBrowserNavigationStarted extends AleraBrowserEvent {
  const AleraBrowserNavigationStarted({
    required super.pageId,
    required super.occurredAt,
    required this.url,
  });

  final Uri url;
}

final class AleraBrowserNavigationCommitted extends AleraBrowserEvent {
  const AleraBrowserNavigationCommitted({
    required super.pageId,
    required super.occurredAt,
    required this.url,
  });

  final Uri url;
}

final class AleraBrowserNavigationFinished extends AleraBrowserEvent {
  const AleraBrowserNavigationFinished({
    required super.pageId,
    required super.occurredAt,
    required this.url,
    this.title,
    this.canGoBack,
    this.canGoForward,
  });

  final Uri url;
  final String? title;
  final bool? canGoBack;
  final bool? canGoForward;
}

final class AleraBrowserUrlChanged extends AleraBrowserEvent {
  const AleraBrowserUrlChanged({
    required super.pageId,
    required super.occurredAt,
    required this.url,
  });

  final Uri url;
}

final class AleraBrowserProgressChanged extends AleraBrowserEvent {
  const AleraBrowserProgressChanged({
    required super.pageId,
    required super.occurredAt,
    required this.progress,
  });

  final double progress;
}

final class AleraBrowserLoadFailed extends AleraBrowserEvent {
  const AleraBrowserLoadFailed({
    required super.pageId,
    required super.occurredAt,
    required this.description,
    this.url,
  });

  final Uri? url;
  final String description;
}

enum AleraBrowserConsoleLevel { debug, info, warning, error, unknown }

final class AleraBrowserConsoleMessage extends AleraBrowserEvent {
  const AleraBrowserConsoleMessage({
    required super.pageId,
    required super.occurredAt,
    required this.level,
    required this.message,
  });

  final AleraBrowserConsoleLevel level;
  final String message;
}

final class AleraBrowserPopupBlocked extends AleraBrowserEvent {
  const AleraBrowserPopupBlocked({
    required super.pageId,
    required super.occurredAt,
    this.url,
  });

  final Uri? url;
}

final class AleraBrowserPageClosed extends AleraBrowserEvent {
  const AleraBrowserPageClosed({
    required super.pageId,
    required super.occurredAt,
  });
}

enum AleraBrowserDownloadState {
  requested,
  inProgress,
  completed,
  cancelled,
  failed,
}

final class AleraBrowserDownloadChanged extends AleraBrowserEvent {
  const AleraBrowserDownloadChanged({
    required super.pageId,
    required super.occurredAt,
    required this.downloadId,
    required this.state,
    required this.receivedBytes,
    this.totalBytes,
    this.suggestedFileName,
    this.destinationPath,
    this.errorCode,
  });

  final String downloadId;
  final AleraBrowserDownloadState state;
  final int receivedBytes;
  final int? totalBytes;
  final String? suggestedFileName;
  final String? destinationPath;
  final String? errorCode;
}
