import 'package:alera/src/features/app_window/domain/app_foreground.dart';
import 'package:alera/src/features/app_window/infra/lifecycle_app_foreground.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/inbox/infra/runtime_inbox_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'inbox_providers.g.dart';

@riverpod
RuntimeInboxRepository inboxRepository(Ref ref) => RuntimeInboxRepository(
  ref.watch(runtimeHostClientProvider),
  ref.watch(runtimeChangeCoalescerProvider),
);

// Recovery is event-driven, including unsupported or disconnected hosts.
Duration? _noInboxRetry(int retryCount, Object error) => null;

@Riverpod(retry: _noInboxRetry)
Stream<InboxSummary> inboxSummary(Ref ref) =>
    ref.watch(inboxRepositoryProvider).watchSummary();

@Riverpod(retry: _noInboxRetry)
Stream<InboxThreadPage> inboxThreads(
  Ref ref, {
  String? inbox,
  InboxQuestionStatus? status,
}) => ref
    .watch(inboxRepositoryProvider)
    .watchThreads(InboxThreadQuery(inbox: inbox, status: status));

@Riverpod(retry: _noInboxRetry)
Stream<InboxThreadDetail> inboxThreadDetail(Ref ref, String threadId) =>
    ref.watch(inboxRepositoryProvider).watchThread(threadId);

@Riverpod(retry: _noInboxRetry)
Future<List<InboxRecipient>> inboxTargets(Ref ref) =>
    ref.watch(inboxRepositoryProvider).readTargets();

/// Unread replies across every inbox, or null when the host cannot answer.
@riverpod
int? inboxUnreadReplyCount(Ref ref) {
  final summary = ref.watch(inboxSummaryProvider);
  return summary.hasError ? null : summary.value?.unreadReplyCount;
}

/// Whether the user can see and act on the app window: visible and focused.
/// Reading a reply and suppressing its notification both depend on it.
@Riverpod(keepAlive: true)
AppForeground inboxWindowFocus(Ref ref) {
  final focus = LifecycleAppForeground(requireFocus: true);
  ref.onDispose(focus.dispose);
  return focus;
}
