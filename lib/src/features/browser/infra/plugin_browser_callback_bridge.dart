import 'package:alera/src/features/browser/application/browser_native_callback_coordinator.dart';
import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/domain/browser_popup.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:alera_browser/alera_browser.dart';

final class PluginBrowserCallbackBridge({
  required BrowserNativeCallbackCoordinator coordinator,
  DateTime Function()? now,
}) {
  this
    : _coordinator = coordinator, // ignore: prefer_initializing_formals
      _now = now ?? _defaultNow;

  final BrowserNativeCallbackCoordinator _coordinator;
  final DateTime Function() _now;
  var _requestSequence = 0;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  AleraBrowserCallbacks get callbacks => AleraBrowserCallbacks(
    onPermissionRequest: _permission,
    onTlsError: _tls,
    onPopupRequest: _popup,
    onDownloadRequest: _download,
  );

  Future<AleraBrowserPermissionDecision> _permission(
    AleraBrowserPermissionRequest request,
  ) async {
    if (request.resources.isEmpty) {
      return AleraBrowserPermissionDecision.deny;
    }
    final decision = await _coordinator.decidePermissions(
      <BrowserPermissionRequest>[
        for (final resource in request.resources)
          BrowserPermissionRequest(
            requestId: 'permission-${++_requestSequence}',
            pageId: request.pageId,
            origin: request.origin?.toString() ?? '',
            permission: browserPermissionTypeFromWire(resource),
            requestedAt: _now(),
          ),
      ],
    );
    return decision == BrowserPermissionDecision.allow
        ? AleraBrowserPermissionDecision.allow
        : AleraBrowserPermissionDecision.deny;
  }

  Future<AleraBrowserTlsDecision> _tls(AleraBrowserTlsError error) async {
    final proceed = await _coordinator.decideTls(
      BrowserTlsRequest(
        pageId: error.pageId,
        host: error.host,
        fingerprintSha256: error.fingerprintSha256,
        url: error.url,
        description: error.description,
        subject: error.subject,
        issuer: error.issuer,
        validFrom: error.validFrom,
        validTo: error.validTo,
        errors: <BrowserTlsErrorType>{
          for (final value in error.errors)
            BrowserTlsErrorType.values.firstWhere(
              (candidate) => candidate.name == value.name,
              orElse: () => BrowserTlsErrorType.other,
            ),
        },
        requestedAt: _now(),
      ),
    );
    return proceed
        ? AleraBrowserTlsDecision.proceed
        : AleraBrowserTlsDecision.cancel;
  }

  Future<AleraBrowserPopupDecision> _popup(
    AleraBrowserPopupRequest request,
  ) async {
    final decision = await _coordinator.decidePopup(
      BrowserPopupRequest(
        requestId: request.requestId,
        openerPageId: request.pageId,
        transientPageId: request.transientPageId,
        url: request.url,
        windowName: request.windowName,
        userInitiated: request.userInitiated,
        trusted: request.trusted,
        requiresOpener: request.requiresOpener,
        requestedAt: _now(),
      ),
    );
    return decision.accepted
        ? AleraBrowserPopupDecision.openInPage(decision.targetPageId!)
        : const AleraBrowserPopupDecision.deny();
  }

  Future<AleraBrowserDownloadDecision> _download(
    AleraBrowserDownloadRequest request,
  ) async {
    final decision = await _coordinator.decideDownload(
      BrowserDownloadRequest(
        pageId: request.pageId,
        url: request.url,
        suggestedFileName: request.suggestedFileName,
        mimeType: request.mimeType,
        totalBytes: request.totalBytes,
        requestedAt: _now(),
      ),
    );
    return decision.accepted
        ? AleraBrowserDownloadDecision.accept(
            destinationPath: decision.destinationPath!,
          )
        : const AleraBrowserDownloadDecision.deny();
  }
}
