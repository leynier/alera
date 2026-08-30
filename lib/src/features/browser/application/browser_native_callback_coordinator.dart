// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/domain/browser_popup.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:path/path.dart' as p;

typedef BrowserPermissionHandler = Future<BrowserPermissionDecision> Function(
  BrowserPermissionRequest request,
  BrowserCallbackCancellation cancellation,
);
typedef BrowserTlsHandler = Future<bool> Function(
  BrowserTlsRequest request,
  BrowserCallbackCancellation cancellation,
);
typedef BrowserPopupHandler = Future<BrowserPopupDecision> Function(
  BrowserPopupRequest request,
  BrowserCallbackCancellation cancellation,
);
typedef BrowserDownloadHandler = Future<BrowserDownloadDecision> Function(
  BrowserDownloadRequest request,
  BrowserCallbackCancellation cancellation,
);

final class BrowserCallbackCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void _cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

final class BrowserNativeCallbackHandlers {
  const BrowserNativeCallbackHandlers({
    this.permission,
    this.tls,
    this.popup,
    this.download,
  });

  final BrowserPermissionHandler? permission;
  final BrowserTlsHandler? tls;
  final BrowserPopupHandler? popup;
  final BrowserDownloadHandler? download;
}

final class BrowserNativeCallbackCoordinator {
  BrowserNativeCallbackCoordinator({
    this.deadline = const Duration(seconds: 15),
    this.tlsDeadline = const Duration(seconds: 60),
    BrowserPermissionHandler? fallbackPermission,
    BrowserPopupHandler? fallbackPopup,
  }) : _fallbackPermission = fallbackPermission,
       _fallbackPopup = fallbackPopup;

  final Duration deadline;
  final Duration tlsDeadline;
  final BrowserPermissionHandler? _fallbackPermission;
  final BrowserPopupHandler? _fallbackPopup;
  BrowserNativeCallbackHandlers? _handlers;
  Object? _registrationIdentity;

  BrowserCallbackRegistration register(BrowserNativeCallbackHandlers handlers) {
    final identity = Object();
    _registrationIdentity = identity;
    _handlers = handlers;
    return BrowserCallbackRegistration._(() {
      if (identical(_registrationIdentity, identity)) {
        _registrationIdentity = null;
        _handlers = null;
      }
    });
  }

  Future<BrowserPermissionDecision> decidePermission(
    BrowserPermissionRequest request,
  ) => decidePermissions(<BrowserPermissionRequest>[request]);

  Future<BrowserPermissionDecision> decidePermissions(
    List<BrowserPermissionRequest> requests,
  ) {
    final handler = _handlers?.permission ?? _fallbackPermission;
    if (handler == null || requests.isEmpty) {
      return Future<BrowserPermissionDecision>.value(
        BrowserPermissionDecision.deny,
      );
    }
    return _guarded((cancellation) async {
      for (final request in requests) {
        if (request.permission == BrowserPermissionType.displayCapture ||
            request.permission == BrowserPermissionType.unknown) {
          return BrowserPermissionDecision.deny;
        }
        final decision = await handler(request, cancellation);
        if (cancellation.isCancelled ||
            decision != BrowserPermissionDecision.allow) {
          return BrowserPermissionDecision.deny;
        }
      }
      return BrowserPermissionDecision.allow;
    }, BrowserPermissionDecision.deny);
  }

  Future<bool> decideTls(BrowserTlsRequest request) {
    final handler = _handlers?.tls;
    return handler == null
        ? Future<bool>.value(false)
        : _guarded(
            (cancellation) => handler(request, cancellation),
            false,
            timeout: tlsDeadline,
          );
  }

  Future<BrowserPopupDecision> decidePopup(BrowserPopupRequest request) {
    final handler = _handlers?.popup ?? _fallbackPopup;
    return handler == null
        ? Future<BrowserPopupDecision>.value(const BrowserPopupDecision.deny())
        : _guarded(
            (cancellation) => handler(request, cancellation),
            const BrowserPopupDecision.deny(),
          );
  }

  Future<BrowserDownloadDecision> decideDownload(
    BrowserDownloadRequest request,
  ) async {
    final handler = _handlers?.download;
    if (handler == null) {
      return const BrowserDownloadDecision.deny();
    }
    final decision = await _guarded(
      (cancellation) => handler(request, cancellation),
      const BrowserDownloadDecision.deny(),
    );
    final destination = decision.destinationPath?.trim();
    if (destination == null ||
        destination.isEmpty ||
        !p.isAbsolute(destination)) {
      return const BrowserDownloadDecision.deny();
    }
    return BrowserDownloadDecision.accept(destination);
  }

  Future<T> _guarded<T>(
    Future<T> Function(BrowserCallbackCancellation cancellation) operation,
    T fallback, {
    Duration? timeout,
  }) async {
    final cancellation = BrowserCallbackCancellation();
    try {
      return await operation(cancellation).timeout(
        timeout ?? deadline,
        onTimeout: () {
          cancellation._cancel();
          return fallback;
        },
      );
    } on Object {
      cancellation._cancel();
      return fallback;
    }
  }
}

final class BrowserCallbackRegistration {
  BrowserCallbackRegistration._(this._release);

  final void Function() _release;
  var _disposed = false;

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _release();
  }
}
