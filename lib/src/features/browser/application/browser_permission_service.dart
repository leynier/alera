import 'package:alera/src/features/browser/domain/browser_permission.dart';

abstract interface class BrowserPermissionService {
  Future<BrowserPermissionDecision> decisionFor({
    required String profileId,
    required String origin,
    required BrowserPermissionType permission,
  });

  Future<void> remember({
    required String profileId,
    required String origin,
    required BrowserPermissionType permission,
    required BrowserPermissionDecision decision,
  });
}
