import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_status_labels.dart';
import 'package:alera_mobile/src/features/automations/presentation/authoring/mobile_automation_authoring_screen.dart';
import 'package:alera_mobile/src/features/automations/presentation/automation_detail_tabs.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_actions.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_run_sheet.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_tone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _RunNowOption { defaults, withoutPrecheck, queue, parallel }

enum _MoreAction { edit, clone, pauseAndCancel, trash, restore }

/// A full screen per automation that follows runtime events while open.
class const AutomationDetailScreen({
  required final String hostId,
  required final String automationId,
  final String? initialRunId,
  super.key,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AutomationDetailScreen> createState() =>
      _AutomationDetailScreenState();
}

class _AutomationDetailScreenState
    extends ConsumerState<AutomationDetailScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.initialRunId case final runId?) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ref.read(
          mobileAutomationDetailProvider(
            widget.hostId,
            widget.automationId,
          ).future,
        );
        if (!mounted) return;
        unawaited(
          showMobileAutomationRun(
            context,
            hostId: widget.hostId,
            automationId: widget.automationId,
            runId: runId,
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailValue = ref.watch(
      mobileAutomationDetailProvider(widget.hostId, widget.automationId),
    );
    final detail = detailValue.value;
    final names =
        ref.watch(mobileAutomationContextProvider(widget.hostId)).value ??
        const MobileAutomationContext();
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Automation')),
        body: Center(
          child: detailValue.hasError
              ? Padding(
                  padding: AleraTokens.pagePadding,
                  child: Text(
                    'This automation is unavailable: ${detailValue.error}',
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      );
    }
    final automation = detail.automation;
    final offline = detailValue.hasError;
    final actions = MobileAutomationActions(
      ref,
      widget.hostId,
      ScaffoldMessenger.of(context),
    );
    final state = automationStateLabel(automation);
    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialRunId == null ? 0 : 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text(automation.name, maxLines: 1, overflow: .ellipsis),
          actions: <Widget>[
            IconButton(
              tooltip: 'More Actions',
              icon: const Icon(AleraIcons.more),
              onPressed: offline
                  ? null
                  : () => unawaited(_more(context, automation, actions)),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Overview'),
              Tab(text: 'Runs'),
              Tab(text: 'Settings'),
              Tab(text: 'Activity'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              Padding(
                padding: AleraTokens.pagePadding,
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: <Widget>[
                    if (offline)
                      const Padding(
                        padding: EdgeInsets.only(bottom: AleraTokens.spaceSm),
                        child: AleraNotice(
                          message: 'Offline. Actions are unavailable until the host reconnects.',
                        ),
                      ),
                    Row(
                      children: <Widget>[
                        AleraBadge(
                          label: state.label,
                          color: mobileAutomationToneColor(state.tone),
                        ),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: AleraTokens.spaceSm),
                    Wrap(
                      spacing: AleraTokens.spaceSm,
                      runSpacing: AleraTokens.spaceSm,
                      children: offline
                          ? const <Widget>[]
                          : _primaryActions(context, automation, actions),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    AutomationDetailOverviewTab(
                      automation: automation,
                      detail: detail,
                      names: names,
                    ),
                    AutomationDetailRunsTab(
                      hostId: widget.hostId,
                      detail: detail,
                    ),
                    AutomationDetailSettingsTab(
                      automation: automation,
                      names: names,
                    ),
                    AutomationDetailActivityTab(events: detail.audit),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _primaryActions(
    BuildContext context,
    AutomationRecord automation,
    MobileAutomationActions actions,
  ) => <Widget>[
    if (automation.state == 'draft')
      FilledButton(
        onPressed: () => unawaited(actions.activate(automation)),
        child: const Text('Activate'),
      ),
    if (automation.state == 'active')
      OutlinedButton(
        onPressed: () => unawaited(actions.pause(automation)),
        child: const Text('Pause'),
      ),
    if (automation.state == 'paused' || automation.state == 'blocked')
      FilledButton(
        onPressed: () => unawaited(actions.resume(automation)),
        child: const Text('Resume'),
      ),
    if (automation.isTrashed)
      FilledButton(
        onPressed: () => unawaited(actions.restore(automation)),
        child: const Text('Restore'),
      )
    else
      FilledButton.tonal(
        onPressed: () => unawaited(_runNow(context, automation, actions)),
        child: Text(automation.isCompleted ? 'Run Again' : 'Run Now'),
      ),
    if (automation.attention != null && automation.isEditable)
      OutlinedButton(
        onPressed: () => unawaited(_edit(context, automation)),
        child: const Text('Fix Problem'),
      ),
  ];

  /// One tap runs with the definition's own policy; the sheet offers the
  /// explicit overrides.
  Future<void> _runNow(
    BuildContext context,
    AutomationRecord automation,
    MobileAutomationActions actions,
  ) async {
    final option = await showAleraActionSheet<_RunNowOption>(
      context,
      entries: <AleraActionSheetEntry<_RunNowOption>>[
        const AleraActionSheetEntry(
          value: _RunNowOption.defaults,
          label: 'Run Now',
          leading: Icon(AleraIcons.agent),
        ),
        if (automation.precheck != null)
          const AleraActionSheetEntry(
            value: _RunNowOption.withoutPrecheck,
            label: 'Run Without Precheck',
            leading: Icon(AleraIcons.cancel),
          ),
        const AleraActionSheetEntry(
          value: _RunNowOption.queue,
          label: 'Queue After Active Run',
          leading: Icon(AleraIcons.queuedMessage),
        ),
        const AleraActionSheetEntry(
          value: _RunNowOption.parallel,
          label: 'Run In Parallel',
          leading: Icon(AleraIcons.split),
        ),
      ],
    );
    final run = await switch (option) {
      null => Future<AutomationRunRecord?>.value(),
      _RunNowOption.defaults => actions.runNow(automation),
      _RunNowOption.withoutPrecheck => actions.runNow(
        automation,
        precheck: false,
      ),
      _RunNowOption.queue => actions.runNow(automation, overlap: 'queue'),
      _RunNowOption.parallel => actions.runNow(
        automation,
        overlap: 'forceParallel',
      ),
    };
    if (run != null && run.id.isNotEmpty && context.mounted) {
      unawaited(
        showMobileAutomationRun(
          context,
          hostId: widget.hostId,
          automationId: automation.id,
          runId: run.id,
        ),
      );
    }
  }

  Future<void> _edit(BuildContext context, AutomationRecord automation) =>
      showMobileAutomationAuthoring(
        context,
        hostId: widget.hostId,
        editing: automation,
      );

  Future<void> _more(
    BuildContext context,
    AutomationRecord automation,
    MobileAutomationActions actions,
  ) async {
    final action = await showAleraActionSheet<_MoreAction>(
      context,
      entries: <AleraActionSheetEntry<_MoreAction>>[
        if (automation.isEditable)
          const AleraActionSheetEntry(
            value: _MoreAction.edit,
            label: 'Edit',
            leading: Icon(AleraIcons.edit),
          ),
        const AleraActionSheetEntry(
          value: _MoreAction.clone,
          label: 'Clone',
          leading: Icon(AleraIcons.copy),
        ),
        if (automation.state == 'active')
          const AleraActionSheetEntry(
            value: _MoreAction.pauseAndCancel,
            label: 'Pause And Cancel Runs',
            leading: Icon(AleraIcons.stop),
          ),
        if (automation.isTrashed)
          const AleraActionSheetEntry(
            value: _MoreAction.restore,
            label: 'Restore',
            leading: Icon(AleraIcons.restore),
          )
        else
          const AleraActionSheetEntry(
            value: _MoreAction.trash,
            label: 'Move To Trash',
            leading: Icon(AleraIcons.delete),
          ),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case null:
        return;
      case _MoreAction.edit:
        await _edit(context, automation);
      case _MoreAction.clone:
        await showMobileAutomationAuthoring(
          context,
          hostId: widget.hostId,
          cloneOf: automation,
        );
      case _MoreAction.pauseAndCancel:
        await actions.pause(automation, cancelRuns: true);
      case _MoreAction.trash:
        await actions.trash(automation);
      case _MoreAction.restore:
        await actions.restore(automation);
    }
  }
}
