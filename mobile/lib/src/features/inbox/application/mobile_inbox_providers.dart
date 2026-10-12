import 'package:alera_mobile/src/features/inbox/domain/inbox_models.dart';
import 'package:alera_mobile/src/features/inbox/infra/mobile_runtime_inbox_repository.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_reader.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_inbox_providers.g.dart';

/// The paired runtime as the Inbox screens see it. Rebuilds with every
/// reconnection, which reloads everything that depends on it.
@riverpod
Future<MobileInboxClient> mobileInboxClient(Ref ref, String hostId) async {
  final client = await watchHostConnection(ref, hostId);
  if (!client.supportsInbox) {
    throw UnsupportedError('This host does not support the inbox');
  }
  return client;
}

@riverpod
Future<MobileRuntimeInboxRepository> mobileInboxRepository(
  Ref ref,
  String hostId,
) async => MobileRuntimeInboxRepository(
  await ref.watch(mobileInboxClientProvider(hostId).future),
);

/// Every inbox of the host with its counts.
@riverpod
class MobileInboxSummary extends _$MobileInboxSummary {
  @override
  Future<List<InboxSummaryEntry>> build(String hostId) async {
    final repository = await ref.watch(
      mobileInboxRepositoryProvider(hostId).future,
    );
    final subscription = repository.changes.listen((_) => ref.invalidateSelf());
    ref.onDispose(subscription.cancel);
    return repository.summary();
  }
}

/// Threads per page; the runtime orders them by latest activity.
const int inboxThreadPageSize = 50;

/// Threads matching the filters, most recent activity first, one page at a
/// time. The runtime filters before it pages, so every page is full. A change
/// or new filters start again from the first page.
@riverpod
class MobileInboxThreads extends _$MobileInboxThreads {
  bool _loadingMore = false;

  @override
  Future<InboxThreadPage> build(
    String hostId, {
    String? inbox,
    InboxQuestionStatus? status,
  }) async {
    final repository = await ref.watch(
      mobileInboxRepositoryProvider(hostId).future,
    );
    final subscription = repository.changes.listen((_) => ref.invalidateSelf());
    ref.onDispose(subscription.cancel);
    return repository.threads(
      inbox: inbox,
      status: status,
      limit: inboxThreadPageSize,
    );
  }

  /// Appends the next page, skipping threads already shown.
  Future<void> loadMore() async {
    final current = state.value;
    final before = current?.nextBefore;
    if (current == null || before == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final repository = await ref.read(
        mobileInboxRepositoryProvider(hostId).future,
      );
      final next = await repository.threads(
        inbox: inbox,
        status: status,
        before: before,
        limit: inboxThreadPageSize,
      );
      if (!ref.mounted || state.value != current) return;
      state = AsyncData(mergeInboxThreadPages(current, next));
    } finally {
      _loadingMore = false;
    }
  }
}

InboxThreadPage mergeInboxThreadPages(
  InboxThreadPage current,
  InboxThreadPage next,
) {
  final seen = <String>{for (final thread in current.items) thread.threadId};
  return InboxThreadPage(
    items: <InboxThread>[
      ...current.items,
      for (final thread in next.items)
        if (seen.add(thread.threadId)) thread,
    ],
    nextBefore: next.nextBefore,
  );
}

/// One thread. Loading never acknowledges it: refreshes also run while the
/// app is in the background, and a read reply is read on every device.
@riverpod
class MobileInboxThreadDetail extends _$MobileInboxThreadDetail {
  @override
  Future<InboxThreadDetail> build(String hostId, String threadId) async {
    final repository = await ref.watch(
      mobileInboxRepositoryProvider(hostId).future,
    );
    final subscription = repository.changes.listen((_) => ref.invalidateSelf());
    ref.onDispose(subscription.cancel);
    return repository.thread(threadId);
  }
}

/// Agents that can be asked, optionally only those of one workspace.
@riverpod
Future<List<InboxRecipient>> mobileInboxTargets(
  Ref ref,
  String hostId, {
  String? workspaceId,
}) async {
  final repository = await ref.watch(
    mobileInboxRepositoryProvider(hostId).future,
  );
  return repository.targets(workspaceId: workspaceId);
}

/// Names of the host's workspaces, to group the agents that can be asked.
@riverpod
Future<Map<String, String>> mobileInboxWorkspaceNames(
  Ref ref,
  String hostId,
) async {
  final client = await ref.watch(mobileInboxClientProvider(hostId).future);
  final workspaces = await client.listWorkspaces();
  return <String, String>{
    for (final workspace in workspaces) workspace.id: workspace.name,
  };
}

class const MobileInboxListState({
  final String? inbox,
  final InboxQuestionStatus? status,
}) {
  bool get isFiltered => inbox != null || status != null;
}

/// Inbox and status filters of the list, kept per host while the app runs.
@Riverpod(keepAlive: true)
class MobileInboxListController extends _$MobileInboxListController {
  @override
  MobileInboxListState build(String hostId) => const MobileInboxListState();

  void setInbox(String? inbox) =>
      state = MobileInboxListState(inbox: inbox, status: state.status);

  void setStatus(InboxQuestionStatus? status) =>
      state = MobileInboxListState(inbox: state.inbox, status: status);

  void clear() => state = const MobileInboxListState();
}

/// Threads matching the list filters.
List<InboxThread> visibleInboxThreads(
  List<InboxThread> threads,
  MobileInboxListState filters,
) => <InboxThread>[
  for (final thread in threads)
    if ((filters.inbox == null || thread.inbox == filters.inbox) &&
        (filters.status == null || thread.status == filters.status))
      thread,
];
