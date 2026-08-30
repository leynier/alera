import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';

sealed class const BrowserEngineEvent({
  required final String pageId,
  required final DateTime occurredAt,
});

final class const BrowserNavigationStarted({
  required super.pageId,
  required super.occurredAt,
  required final Uri url,
}) extends BrowserEngineEvent;

final class const BrowserNavigationCommitted({
  required super.pageId,
  required super.occurredAt,
  required final Uri url,
}) extends BrowserEngineEvent;

final class const BrowserNavigationFinished({
  required super.pageId,
  required super.occurredAt,
  required final Uri url,
  required final String title,
  final bool? canGoBack,
  final bool? canGoForward,
}) extends BrowserEngineEvent;

final class const BrowserUrlChanged({
  required super.pageId,
  required super.occurredAt,
  required final Uri url,
}) extends BrowserEngineEvent;

final class const BrowserProgressChanged({
  required super.pageId,
  required super.occurredAt,
  required final double progress,
}) extends BrowserEngineEvent;

final class const BrowserLoadFailed({
  required super.pageId,
  required super.occurredAt,
  required final BrowserFailure failure,
  final Uri? url,
}) extends BrowserEngineEvent;

final class const BrowserSecurityChanged({
  required super.pageId,
  required super.occurredAt,
  required final BrowserSecurityState security,
}) extends BrowserEngineEvent;

final class const BrowserDownloadChanged({
  required super.pageId,
  required super.occurredAt,
  required final BrowserDownload download,
}) extends BrowserEngineEvent;

final class const BrowserPermissionRequested({
  required super.pageId,
  required super.occurredAt,
  required final BrowserPermissionRequest request,
}) extends BrowserEngineEvent;

final class const BrowserPopupRequested({
  required super.pageId,
  required super.occurredAt,
  required final String requestId,
  required final Uri url,
  required final bool userGesture,
  required final bool trusted,
  required final bool requiresOpener,
}) extends BrowserEngineEvent;

final class const BrowserPageClosed({
  required super.pageId,
  required super.occurredAt,
}) extends BrowserEngineEvent;

final class const BrowserConsoleMessage({
  required super.pageId,
  required super.occurredAt,
  required final BrowserConsoleLevel level,
  required final String message,
}) extends BrowserEngineEvent;

enum BrowserConsoleLevel { debug, info, warning, error }
