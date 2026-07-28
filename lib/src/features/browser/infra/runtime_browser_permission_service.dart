import 'package:alera/src/features/browser/application/browser_permission_service.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_payload.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

final class RuntimeBrowserPermissionService
    implements BrowserPermissionService {
  const RuntimeBrowserPermissionService(this._client);

  final RuntimeHostClient _client;

  @override
  Future<BrowserPermissionDecision> decisionFor({
    required String profileId,
    required String origin,
    required BrowserPermissionType permission,
  }) async {
    if (permission == BrowserPermissionType.displayCapture ||
        permission == BrowserPermissionType.unknown) {
      return BrowserPermissionDecision.deny;
    }
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest(
        'browser.permissions.list',
        <String, Object?>{'profileId': profileId, 'origin': origin},
      ),
      'Browser permission list',
    );
    for (final value in browserRuntimeList(response, 'permissions')) {
      final item = browserRuntimeItem(value, 'Browser permission');
      if (item['permission'] == permission.name) {
        return _decisionFromWire(item['decision']);
      }
    }
    return BrowserPermissionDecision.ask;
  }

  @override
  Future<void> remember({
    required String profileId,
    required String origin,
    required BrowserPermissionType permission,
    required BrowserPermissionDecision decision,
  }) async {
    if (permission == BrowserPermissionType.displayCapture ||
        permission == BrowserPermissionType.unknown ||
        decision == BrowserPermissionDecision.ask) {
      return;
    }
    browserRuntimeSuccessMap(
      await _client.runtimeRequest('browser.permissions.set', <String, Object?>{
        'profileId': profileId,
        'origin': origin,
        'permission': permission.name,
        'decision': decision.name,
      }),
      'Browser permission update',
    );
  }
}

BrowserPermissionDecision _decisionFromWire(Object? value) {
  return switch (value) {
    'allow' => BrowserPermissionDecision.allow,
    'deny' => BrowserPermissionDecision.deny,
    _ => BrowserPermissionDecision.ask,
  };
}
