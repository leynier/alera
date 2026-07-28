import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:alera/src/features/browser/domain/browser_engine_event.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine event variants retain their callback payloads', () {
    final occurredAt = DateTime.utc(2026, 7, 27);
    final url = Uri.parse('https://example.com');
    final security = BrowserSecurityState(
      level: BrowserSecurityLevel.secure,
      origin: url.origin,
    );
    final permission = BrowserPermissionRequest(
      requestId: 'permission-1',
      pageId: 'page-1',
      origin: url.origin,
      permission: BrowserPermissionType.geolocation,
      requestedAt: occurredAt,
    );

    final urlChanged = BrowserUrlChanged(
      pageId: 'page-1',
      occurredAt: occurredAt,
      url: url,
    );
    final securityChanged = BrowserSecurityChanged(
      pageId: 'page-1',
      occurredAt: occurredAt,
      security: security,
    );
    final permissionRequested = BrowserPermissionRequested(
      pageId: 'page-1',
      occurredAt: occurredAt,
      request: permission,
    );
    final popupRequested = BrowserPopupRequested(
      pageId: 'page-1',
      occurredAt: occurredAt,
      requestId: 'popup-1',
      url: url,
      userGesture: true,
      trusted: true,
      requiresOpener: false,
    );
    final consoleMessage = BrowserConsoleMessage(
      pageId: 'page-1',
      occurredAt: occurredAt,
      level: BrowserConsoleLevel.warning,
      message: 'A warning',
    );
    final downloadChanged = BrowserDownloadChanged(
      pageId: 'page-1',
      occurredAt: occurredAt,
      download: BrowserDownload(
        id: 'download-1',
        pageId: 'page-1',
        fileName: 'file.txt',
        status: BrowserDownloadStatus.pending,
        receivedBytes: 0,
        startedAt: occurredAt,
      ),
    );

    expect(urlChanged.url, url);
    expect(securityChanged.security, same(security));
    expect(permissionRequested.request, same(permission));
    expect(popupRequested.requestId, 'popup-1');
    expect(popupRequested.userGesture, isTrue);
    expect(consoleMessage.level, BrowserConsoleLevel.warning);
    expect(consoleMessage.message, 'A warning');
    expect(downloadChanged.download.id, 'download-1');
    expect(urlChanged.occurredAt, occurredAt);
  });
}
