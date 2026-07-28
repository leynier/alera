import 'package:alera/src/features/browser/application/browser_session_registry.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

typedef BrowserTabProfilePersistence = Future<WorkspaceTabRecord> Function();

Future<BrowserSessionHandle> switchBrowserSessionProfile({
  required BrowserSessionRegistry registry,
  required BrowserSessionHandle currentSession,
  required WorkspaceTabRecord currentTab,
  required BrowserTabProfilePersistence persist,
}) async {
  if (currentSession.pageId != currentTab.id) {
    throw StateError('The Browser Session Does Not Match The Current Tab.');
  }
  final updatedTab = await persist();
  return registry.reconcilePersistentSession(updatedTab);
}
