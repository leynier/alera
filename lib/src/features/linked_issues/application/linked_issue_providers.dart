import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/linked_issues/application/linked_issue_metadata_refresher.dart';
import 'package:alera/src/features/linked_issues/application/linked_issue_repository.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue.dart';
import 'package:alera/src/features/linked_issues/domain/linked_issue_snapshot.dart';
import 'package:alera/src/features/linked_issues/infra/runtime_linked_issue_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'linked_issue_providers.g.dart';

@Riverpod(keepAlive: true)
LinkedIssueRepository linkedIssueRepository(Ref ref) {
  return RuntimeLinkedIssueRepository(
    ref.watch(runtimeHostClientProvider),
    beforeAccess: ref.watch(runtimeStateMigrationProvider).ensureMigrated,
    coalescer: ref.watch(runtimeChangeCoalescerProvider),
  );
}

/// Host support plus every linked issue. Watching it also keeps the cached
/// metadata fresh while the window is visible.
@Riverpod(keepAlive: true)
Stream<LinkedIssueSnapshot> linkedIssueSnapshot(Ref ref) {
  final repository = ref.watch(linkedIssueRepositoryProvider);
  final refresher = LinkedIssueMetadataRefresher(
    list: repository.listAll,
    refresh: repository.refresh,
    foreground: ref.watch(appForegroundProvider),
  );
  ref.onDispose(refresher.dispose);
  return repository.watchSnapshot();
}

/// Whether the connected host advertises linked issues. False until the first
/// snapshot arrives, so no control is offered that an older host would reject.
@riverpod
bool linkedIssuesSupported(Ref ref) {
  return ref.watch(linkedIssueSnapshotProvider).value?.supported ?? false;
}

/// The linked issue of one workspace, or null. Selects from the shared
/// snapshot so a sidebar with many rows costs one host request per change;
/// a row rebuilds only when its own link changes.
@riverpod
LinkedIssue? workspaceLinkedIssue(Ref ref, String workspaceId) {
  return ref.watch(linkedIssueSnapshotProvider).value?.byWorkspace[workspaceId];
}
