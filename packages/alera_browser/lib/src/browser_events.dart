sealed class const AleraBrowserEvent({
  required final String pageId,
  required final DateTime occurredAt,
});

final class const AleraBrowserNavigationStarted({
  required super.pageId,
  required super.occurredAt,
  required final Uri url,
}) extends AleraBrowserEvent;

final class const AleraBrowserNavigationCommitted({
  required super.pageId,
  required super.occurredAt,
  required final Uri url,
}) extends AleraBrowserEvent;

final class const AleraBrowserNavigationFinished({
  required super.pageId,
  required super.occurredAt,
  required final Uri url,
  final String? title,
  final bool? canGoBack,
  final bool? canGoForward,
}) extends AleraBrowserEvent;

final class const AleraBrowserUrlChanged({
  required super.pageId,
  required super.occurredAt,
  required final Uri url,
}) extends AleraBrowserEvent;

final class const AleraBrowserProgressChanged({
  required super.pageId,
  required super.occurredAt,
  required final double progress,
}) extends AleraBrowserEvent;

final class const AleraBrowserLoadFailed({
  required super.pageId,
  required super.occurredAt,
  required final String description,
  final Uri? url,
}) extends AleraBrowserEvent;

enum AleraBrowserConsoleLevel { debug, info, warning, error, unknown }

final class const AleraBrowserConsoleMessage({
  required super.pageId,
  required super.occurredAt,
  required final AleraBrowserConsoleLevel level,
  required final String message,
}) extends AleraBrowserEvent;

final class const AleraBrowserPopupBlocked({
  required super.pageId,
  required super.occurredAt,
  final Uri? url,
}) extends AleraBrowserEvent;

final class const AleraBrowserPageClosed({
  required super.pageId,
  required super.occurredAt,
}) extends AleraBrowserEvent;

enum AleraBrowserDownloadState {
  requested,
  inProgress,
  completed,
  cancelled,
  failed,
}

final class const AleraBrowserDownloadChanged({
  required super.pageId,
  required super.occurredAt,
  required final String downloadId,
  required final AleraBrowserDownloadState state,
  required final int receivedBytes,
  final int? totalBytes,
  final String? suggestedFileName,
  final String? destinationPath,
  final String? errorCode,
}) extends AleraBrowserEvent;
