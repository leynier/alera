import 'dart:async';

import 'browser_errors.dart';
import 'browser_models.dart';
import 'dom_automation.dart';

typedef AleraBrowserJavaScriptEvaluator =
    Future<Object?> Function(String pageId, String script);
typedef AleraBrowserAutomationGeneration = int Function(String pageId);

final class AleraNativeBrowserAutomation {
  AleraNativeBrowserAutomation({
    required this.evaluate,
    required this.generation,
    required this.now,
    required this.namespace,
  });

  final AleraBrowserJavaScriptEvaluator evaluate;
  final AleraBrowserAutomationGeneration generation;
  final DateTime Function() now;
  final String namespace;
  final Map<String, int> _snapshotSequences = <String, int>{};

  void invalidate(String pageId) {
    _snapshotSequences.remove(pageId);
    try {
      final invalidation = evaluate(
        pageId,
        aleraBrowserInvalidateAutomationScript,
      );
      unawaited(invalidation.catchError((Object _) => null));
    } on Object {
      // The page may have closed between invalidation and native dispatch.
    }
  }

  Future<AleraBrowserSnapshot> snapshot(
    String pageId,
    AleraBrowserSnapshotOptions options,
  ) async {
    final sequence = (_snapshotSequences[pageId] ?? 0) + 1;
    _snapshotSequences[pageId] = sequence;
    final raw = await evaluate(
      pageId,
      aleraBrowserSnapshotScript(
        namespace: namespace,
        pageId: pageId,
        pageGeneration: generation(pageId),
        snapshotId: 's$sequence',
        includeSameOriginFrames: options.includeSameOriginFrames,
        interactiveOnly: options.interactiveOnly,
        maxNodes: options.maxNodes,
      ),
    );
    final snapshot = decodeAleraBrowserSnapshot(pageId, raw);
    if (options.failOnCrossOriginFrames &&
        snapshot.blockedCrossOriginFrameCount > 0) {
      throw const AleraBrowserUnsupportedError(
        'cross_origin_frame_automation_unavailable',
        'The page contains a cross-origin frame that cannot be automated.',
      );
    }
    return snapshot;
  }

  Future<void> performAction(String pageId, AleraBrowserAction action) async {
    final raw = await evaluate(pageId, aleraBrowserActionScript(action));
    validateAleraBrowserActionResult(raw);
  }

  Future<void> waitFor(
    String pageId,
    AleraBrowserWaitCondition condition, {
    required Duration timeout,
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
    final deadline = now().add(timeout);
    final script = aleraBrowserWaitScript(condition);
    while (now().isBefore(deadline)) {
      final raw = await evaluate(pageId, script);
      if (decodeAleraBrowserJavaScriptJson(raw) == true) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw AleraBrowserStateError(
      'wait_timeout',
      'Browser wait for ${condition.kind.name} timed out.',
    );
  }
}
