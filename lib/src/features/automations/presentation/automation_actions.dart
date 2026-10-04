import 'dart:async';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/application/automation_terminal_observation.dart';
import 'package:alera/src/features/automations/application/automations_navigation.dart';
import 'package:alera/src/features/automations/domain/automation_models.dart';
import 'package:alera/src/features/automations/infra/runtime_automation_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User actions shared by the page, the detail and the status bar. Each one
/// reports what the runtime actually did instead of assuming success.
extension type const AutomationActions(WidgetRef ref) {
  RuntimeAutomationRepository get _repository =>
      ref.read(automationRepositoryProvider);

  Future<void> _attempt(
    Future<void> Function() action, {
    String? success,
  }) async {
    try {
      await action();
      if (success != null) {
        AleraToast.publish(message: success, tone: AleraToastTone.success);
      }
    } catch (error) {
      AleraToast.publish(message: '$error', tone: AleraToastTone.error);
    }
  }

  /// Runs once without changing the schedule. Defaults come from the
  /// definition; the toast follows the status the runtime returned.
  Future<AutomationRunRecord?> runNow(
    AutomationRecord automation, {
    bool? precheck,
    String? overlap,
    String? continueFromRunId,
  }) async {
    try {
      final run = await _repository.runNow(
        automation.id,
        precheck: precheck,
        overlap: overlap,
        continueFromRunId: continueFromRunId,
      );
      final (message, tone) = automationRunNowFeedback(run);
      AleraToast.publish(message: message, tone: tone);
      if (run.id.isNotEmpty) {
        ref
            .read(automationsNavigationProvider.notifier)
            .selectRun(automation.id, run.id);
      }
      return run;
    } catch (error) {
      AleraToast.publish(message: '$error', tone: AleraToastTone.error);
      return null;
    }
  }

  Future<void> pause(AutomationRecord automation, {bool cancelRuns = false}) =>
      _attempt(
        () => _repository.setState(
          'automation.pause',
          automation.id,
          activeRuns: cancelRuns ? 'cancel-active' : 'continue-active',
        ),
        success: cancelRuns
            ? 'Automation paused and its active runs were asked to cancel.'
            : 'Automation paused. Active runs keep going.',
      );

  Future<void> resume(AutomationRecord automation) => _attempt(
    () => _repository.setState('automation.resume', automation.id),
    success: 'Automation scheduled again.',
  );

  /// Activates a draft. `automation.approve` is the activation verb every
  /// runtime understands; it no longer gates anything.
  Future<void> activate(AutomationRecord automation) => _attempt(
    () => _repository.activate(automation),
    success: 'Automation is active.',
  );

  Future<void> trash(AutomationRecord automation) => _attempt(
    () => _repository.setState('automation.trash', automation.id),
    success: 'Automation moved to Trash.',
  );

  Future<void> restore(AutomationRecord automation) => _attempt(
    () => _repository.setState('automation.restore', automation.id),
    success: 'Automation restored.',
  );

  Future<void> cancelRun(AutomationRunRecord run) => _attempt(
    () => _repository.cancel(run),
    success: 'Cancellation requested for run #${run.number}.',
  );

  Future<void> resumeWaiting(AutomationRunRecord run) => _attempt(
    () => _repository.resumeWaiting(run),
    success: 'Run #${run.number} resumed.',
  );

  Future<void> extendWaiting(AutomationRunRecord run) => _attempt(
    () => _repository.extendWaiting(run),
    success: 'Run #${run.number} can wait one more hour.',
  );

  /// Opens the run's tab. With observation support the tab attaches read-only
  /// and nothing is taken over; without it the attach takes the run over,
  /// which is why that button is labelled "Open And Take Over".
  Future<void> openRunTerminal(AutomationRunRecord run) =>
      openTerminalTab(run.workspaceId, run.tabId, label: 'run #${run.number}');

  /// Every recovery attempt has its own tab; each one can be watched.
  Future<void> openTerminalTab(
    String? workspaceId,
    String? tabId, {
    required String label,
  }) async {
    final workbench = ref.read(workbenchControllerProvider);
    final workspace = workbench.workspacesByProject.values
        .expand((items) => items)
        .where((item) => item.id == workspaceId)
        .firstOrNull;
    final project = workbench.projects
        .where((item) => item.id == workspace?.projectId)
        .firstOrNull;
    final tabOpen =
        workspaceId != null &&
        workbench.tabsFor(workspaceId).any((tab) => tab.id == tabId);
    if (workspace == null || project == null || tabId == null || !tabOpen) {
      AleraToast.publish(
        message: 'The terminal of $label is no longer open.',
        tone: AleraToastTone.info,
      );
      return;
    }
    final controller = ref.read(workbenchControllerProvider.notifier);
    ref.read(automationsNavigationProvider.notifier).close();
    await controller.selectWorkspace(project: project, workspace: workspace);
    await controller.selectWorkspaceTab(
      workspaceId: workspace.id,
      tabId: tabId,
    );
  }

  Future<void> openRunWorkspace(AutomationRunRecord run) async {
    final workbench = ref.read(workbenchControllerProvider);
    final workspace = workbench.workspacesByProject.values
        .expand((items) => items)
        .where((item) => item.id == run.workspaceId)
        .firstOrNull;
    final project = workbench.projects
        .where((item) => item.id == workspace?.projectId)
        .firstOrNull;
    if (workspace == null || project == null) {
      AleraToast.publish(
        message: 'The workspace of run #${run.number} is no longer available.',
        tone: AleraToastTone.info,
      );
      return;
    }
    ref.read(automationsNavigationProvider.notifier).close();
    await ref
        .read(workbenchControllerProvider.notifier)
        .selectWorkspace(project: project, workspace: workspace);
  }

  /// Explicit takeover: input becomes available and recovery stops for this
  /// run. The tab re-attaches in normal mode right away.
  Future<void> takeOver(AutomationRunRecord run) =>
      takeOverTab(runId: run.id, tabId: run.tabId);

  Future<void> takeOverTab({required String runId, String? tabId}) async {
    try {
      await _repository.takeOver(runId);
      if (tabId != null) {
        ref.read(automationTakenOverTabsProvider.notifier).mark(tabId);
        unawaited(
          ref.read(terminalRuntimeProvider).peekSession(tabId)?.reconnect(),
        );
      }
      AleraToast.publish(
        message: 'You took over this run. Automatic recovery stopped.',
        tone: AleraToastTone.success,
      );
    } catch (error) {
      AleraToast.publish(message: '$error', tone: AleraToastTone.error);
    }
  }
}

(String, AleraToastTone) automationRunNowFeedback(AutomationRunRecord run) =>
    switch (run.status) {
      'pending' ||
      'dispatching' ||
      'dispatched' => ('Run #${run.number} started.', AleraToastTone.success),
      'overlapSkipped' => (
        'Skipped because a previous run is still active. Use Run Now > Queue After Active Run to wait for it.',
        AleraToastTone.info,
      ),
      'precheckSkipped' => (
        'The precheck skipped this run. Use Run Now > Run Without Precheck to run it anyway.',
        AleraToastTone.info,
      ),
      'queueLimitSkipped' => (
        'Skipped because the run queue is full.',
        AleraToastTone.info,
      ),
      'success' => ('Run #${run.number} finished.', AleraToastTone.success),
      _ => (
        'Run #${run.number} did not start: ${run.error ?? run.status}.',
        AleraToastTone.error,
      ),
    };
