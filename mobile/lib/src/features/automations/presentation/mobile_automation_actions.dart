import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User actions with honest feedback: each message follows what the runtime
/// actually did.
class MobileAutomationActions {
  MobileAutomationActions(this.ref, this.hostId, this.messenger);

  final WidgetRef ref;
  final String hostId;
  final ScaffoldMessengerState messenger;

  Future<MobileRuntimeAutomationRepository> get _repository =>
      ref.read(mobileAutomationRepositoryProvider(hostId).future);

  void show(String message, {bool error = false}) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AleraTokens.error : null,
      ),
    );
  }

  Future<bool> _attempt(Future<void> Function() action, String success) async {
    try {
      await action();
      show(success);
      return true;
    } on Object catch (error) {
      show('$error', error: true);
      return false;
    }
  }

  Future<AutomationRunRecord?> runNow(
    AutomationRecord automation, {
    bool? precheck,
    String? overlap,
    String? continueFromRunId,
  }) async {
    try {
      final run = await (await _repository).runNow(
        automation.id,
        precheck: precheck,
        overlap: overlap,
        continueFromRunId: continueFromRunId,
      );
      final (message, isError) = mobileRunNowFeedback(run);
      show(message, error: isError);
      return run;
    } on Object catch (error) {
      show('$error', error: true);
      return null;
    }
  }

  Future<bool> activate(AutomationRecord automation) => _attempt(
    () async => (await _repository).activate(automation),
    'Automation is active.',
  );

  Future<bool> pause(AutomationRecord automation, {bool cancelRuns = false}) =>
      _attempt(
        () async =>
            (await _repository).pause(automation.id, cancelRuns: cancelRuns),
        cancelRuns
            ? 'Automation paused and its active runs were asked to cancel.'
            : 'Automation paused. Active runs keep going.',
      );

  Future<bool> resume(AutomationRecord automation) => _attempt(
    () async => (await _repository).resume(automation.id),
    'Automation scheduled again.',
  );

  Future<bool> trash(AutomationRecord automation) => _attempt(
    () async => (await _repository).trash(automation.id),
    'Automation moved to Trash.',
  );

  Future<bool> restore(AutomationRecord automation) => _attempt(
    () async => (await _repository).restore(automation.id),
    'Automation restored.',
  );

  Future<bool> cancelRun(AutomationRunRecord run) => _attempt(
    () async => (await _repository).cancel(run),
    'Cancellation requested for run #${run.number}.',
  );

  Future<bool> resumeWaiting(AutomationRunRecord run) => _attempt(
    () async => (await _repository).resumeWaiting(run),
    'Run #${run.number} resumed.',
  );

  Future<bool> extendWaiting(AutomationRunRecord run) => _attempt(
    () async => (await _repository).extendWaiting(run),
    'Run #${run.number} can wait one more hour.',
  );

  /// Explicit takeover: typing becomes possible and recovery stops for the
  /// run. The tab re-attaches normally right away.
  Future<bool> takeOver(String runId, {String? tabId}) async {
    final taken = await _attempt(
      () async => (await _repository).takeOver(runId),
      'You took over this run. Automatic recovery stopped.',
    );
    if (taken && tabId != null) {
      ref
          .read(mobileAutomationTakenOverTabsProvider(hostId).notifier)
          .mark(tabId);
    }
    return taken;
  }
}

(String, bool) mobileRunNowFeedback(AutomationRunRecord run) =>
    switch (run.status) {
      'pending' ||
      'dispatching' ||
      'dispatched' => ('Run #${run.number} started.', false),
      'overlapSkipped' => (
        'Skipped because a previous run is still active. Use Run Now options to queue it.',
        false,
      ),
      'precheckSkipped' => (
        'The precheck skipped this run. Use Run Now options to run without it.',
        false,
      ),
      'queueLimitSkipped' => ('Skipped because the run queue is full.', false),
      'success' => ('Run #${run.number} finished.', false),
      _ => (
        'Run #${run.number} did not start: ${run.error ?? run.status}.',
        true,
      ),
    };
