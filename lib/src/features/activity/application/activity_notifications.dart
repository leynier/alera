import 'dart:async';
import 'dart:convert';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/application/run_attention_link.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/inbox/application/inbox_providers.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/domain/run_gate.dart';
import 'package:alera/src/features/runs/domain/run_summary.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'activity_notifications.g.dart';

const String _runNotificationKind = 'runAttention';

// One id, so a newer run notification replaces the previous one.
const int _runNotificationId = 0x52554E41;

/// Decides when a growing attention count deserves a system notification,
/// and which run it is about: the first attention run not seen before.
class RunAttentionNotificationTracker {
  int? _lastCount;
  Set<String> _seen = <String>{};

  /// The run to announce, or null. The first page seen is a baseline: runs
  /// already waiting when the app starts are not news.
  RunSummary? observe(RunBoardPage page, {required bool activityVisible}) {
    final previous = _lastCount;
    final seen = _seen;
    final count = page.counts.attention;
    _lastCount = count;
    _seen = <String>{for (final run in page.items) run.id};
    if (previous == null || activityVisible || count <= previous) return null;
    return page.items.where((run) => !seen.contains(run.id)).firstOrNull ??
        page.items.firstOrNull;
  }
}

String encodeRunNotificationPayload(String runId, {String? gateId}) =>
    jsonEncode(<String, String>{
      'kind': _runNotificationKind,
      'runId': runId,
      'gateId': ?gateId,
    });

/// The run (and gate, when the host named one) of a run notification
/// payload, or null for other payloads.
({String runId, String? gateId})? decodeRunNotificationPayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map &&
        decoded['kind'] == _runNotificationKind &&
        decoded['runId'] is String) {
      final gateId = decoded['gateId'];
      return (
        runId: decoded['runId'] as String,
        gateId: gateId is String ? gateId : null,
      );
    }
  } on FormatException {
    return null;
  }
  return null;
}

AgentStatusNotification runAttentionNotification(RunSummary run) {
  final gate = run.pendingGates.firstOrNull;
  final planWaiting = gate == null
      ? run.planGatePending || run.pendingGateKinds.contains('plan')
      : gate.kind == RunGateKind.plan;
  return AgentStatusNotification(
    id: _runNotificationId,
    title: 'Run Needs Attention',
    body: planWaiting
        ? 'A plan is waiting for your approval.'
        : 'A gate is waiting for your decision.',
    payload: encodeRunNotificationPayload(run.id, gateId: gate?.id),
  );
}

/// Unlike the board on screen, this read keeps running while the window is
/// hidden: that is exactly when a notification is useful. It only exists
/// while agent notifications are on.
@Riverpod(retry: _noRetry)
Stream<RunBoardPage> runAttentionFeed(Ref ref) {
  final enabled = ref
      .watch(settingsControllerProvider)
      .agents
      .agentStatusNotificationsEnabled;
  if (!enabled) return const Stream<RunBoardPage>.empty();
  return ref
      .watch(runRepositoryProvider)
      .watchBoard(const RunBoardQuery(bucket: RunBucket.attention, limit: 5));
}

Duration? _noRetry(int count, Object error) => null;

/// Shows "Run Needs Attention" when more runs need a decision while Activity
/// is not visible in a focused window. The body never names the run.
@riverpod
void runAttentionNotificationCoordinator(Ref ref) {
  final presenter = ref.watch(agentStatusNotificationPresenterProvider);
  final windowActivator = ref.watch(
    agentStatusNotificationWindowActivatorProvider,
  );
  final tracker = RunAttentionNotificationTracker();
  Future<void>? initializing;

  Future<void> ensureInitialized() => initializing ??= presenter.initialize(
    onSelected: (payload) {
      final target = decodeRunNotificationPayload(payload);
      if (target == null) return;
      unawaited(() async {
        await windowActivator.showAndFocus();
        if (!ref.mounted) return;
        await openRunAttention(
          ref.read(runRepositoryProvider),
          ref.read(activityNavigationProvider.notifier),
          target.runId,
          gateId: target.gateId,
          mounted: () => ref.mounted,
        );
      }());
    },
  );

  ref.listen(runAttentionFeedProvider, (_, next) {
    final page = next.value;
    if (page == null || next.hasError) return;
    final run = tracker.observe(
      page,
      activityVisible:
          ref.read(activityNavigationProvider).visible &&
          ref.read(inboxWindowFocusProvider).isForeground,
    );
    if (run == null) return;
    unawaited(
      ensureInitialized().then(
        (_) => presenter.show(runAttentionNotification(run)),
      ),
    );
  }, fireImmediately: true);
}
