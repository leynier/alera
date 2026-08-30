import 'dart:async';

import 'package:alera/src/features/browser/application/browser_native_callback_coordinator.dart';
import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('denies security-sensitive callbacks by default', () async {
    final coordinator = BrowserNativeCallbackCoordinator();

    expect(
      await coordinator.decidePermission(_permission()),
      BrowserPermissionDecision.deny,
    );
    expect(
      await coordinator.decidePermission(
        _permission(permission: BrowserPermissionType.displayCapture),
      ),
      BrowserPermissionDecision.deny,
    );
  });

  test('registered permission handler can allow geolocation', () async {
    final coordinator = BrowserNativeCallbackCoordinator();
    final registration = coordinator.register(
      BrowserNativeCallbackHandlers(
        permission: (request, _) async {
          expect(request.permission, BrowserPermissionType.geolocation);
          return BrowserPermissionDecision.allow;
        },
      ),
    );

    expect(
      await coordinator.decidePermission(
        _permission(permission: BrowserPermissionType.geolocation),
      ),
      BrowserPermissionDecision.allow,
    );
    registration.dispose();
    expect(
      await coordinator.decidePermission(
        _permission(permission: BrowserPermissionType.geolocation),
      ),
      BrowserPermissionDecision.deny,
    );
  });

  test('download destination must be absolute', () async {
    final coordinator = BrowserNativeCallbackCoordinator();
    coordinator.register(
      BrowserNativeCallbackHandlers(
        download: (_, _) async =>
            const BrowserDownloadDecision.accept('relative/file.zip'),
      ),
    );

    final decision = await coordinator.decideDownload(
      BrowserDownloadRequest(
        pageId: 'page',
        url: Uri.parse('https://example.com/file.zip'),
        requestedAt: DateTime.utc(2026),
      ),
    );

    expect(decision.accepted, isFalse);
  });

  test('deadline falls back to deny', () async {
    final coordinator = BrowserNativeCallbackCoordinator(
      deadline: const Duration(milliseconds: 1),
    );
    late BrowserCallbackCancellation cancellation;
    coordinator.register(
      BrowserNativeCallbackHandlers(
        permission: (_, value) {
          cancellation = value;
          return Completer<BrowserPermissionDecision>().future;
        },
      ),
    );

    expect(
      await coordinator.decidePermission(_permission()),
      BrowserPermissionDecision.deny,
    );
    expect(cancellation.isCancelled, isTrue);
  });

  test('one deadline bounds every resource in a permission request', () async {
    final coordinator = BrowserNativeCallbackCoordinator(
      deadline: const Duration(milliseconds: 10),
    );
    var calls = 0;
    coordinator.register(
      BrowserNativeCallbackHandlers(
        permission: (_, cancellation) async {
          calls += 1;
          if (calls == 1) {
            return BrowserPermissionDecision.allow;
          }
          await cancellation.whenCancelled;
          return BrowserPermissionDecision.allow;
        },
      ),
    );

    expect(
      await coordinator.decidePermissions(<BrowserPermissionRequest>[
        _permission(permission: BrowserPermissionType.camera),
        _permission(permission: BrowserPermissionType.microphone),
      ]),
      BrowserPermissionDecision.deny,
    );
    expect(calls, 2);
  });

  test('TLS decisions use the dedicated user prompt deadline', () async {
    final coordinator = BrowserNativeCallbackCoordinator(
      deadline: const Duration(milliseconds: 1),
      tlsDeadline: const Duration(milliseconds: 100),
    );
    coordinator.register(
      BrowserNativeCallbackHandlers(
        tls: (_, _) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return true;
        },
      ),
    );

    expect(
      await coordinator.decideTls(
        BrowserTlsRequest(
          pageId: 'page',
          host: 'localhost',
          fingerprintSha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          requestedAt: DateTime.utc(2026),
        ),
      ),
      isTrue,
    );
  });
}

BrowserPermissionRequest _permission({
  BrowserPermissionType permission = BrowserPermissionType.camera,
}) {
  return BrowserPermissionRequest(
    requestId: 'request',
    pageId: 'page',
    origin: 'https://example.com',
    permission: permission,
    requestedAt: DateTime.utc(2026),
  );
}
