import 'dart:async';

import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_providers.dart';
import 'package:alera_mobile/src/features/automations/presentation/detail/mobile_automation_binding_card.dart';
import 'package:alera_mobile/src/features/automations/presentation/detail/mobile_automation_detail_actions.dart';
import 'package:alera_mobile/src/features/automations/presentation/detail/mobile_automation_detail_facts.dart';
import 'package:alera_mobile/src/features/automations/presentation/detail/mobile_automation_history.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_actions.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_run_sheet.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_tone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One automation as a full screen that follows runtime events while open:
/// its actions and problems, the facts, the reuse binding, the prompt, then
/// its runs or activity.
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
    final provider = mobileAutomationDetailProvider(
      widget.hostId,
      widget.automationId,
    );
    final detailValue = ref.watch(provider);
    final detail = detailValue.value;
    final names =
        ref.watch(mobileAutomationContextProvider(widget.hostId)).value ??
        const MobileAutomationContext();
    final supportsReuse =
        ref
            .watch(mobileAutomationRepositoryProvider(widget.hostId))
            .value
            ?.supportsReuse ??
        false;
    if (detail == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Automation')),
        body: detailValue.hasError
            ? AleraEmptyState(
                icon: AleraIcons.loadFailed,
                title: 'Automation Unavailable',
                message: automationErrorMessage(detailValue.error),
                action: FilledButton(
                  onPressed: () => ref.invalidate(provider),
                  child: const Text('Retry'),
                ),
              )
            : const Center(child: CircularProgressIndicator()),
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
    final readiness = automation.readiness;
    final theme = Theme.of(context);
    final sections = <Widget>[
      if (offline)
        const AleraNotice(
          message:
              'Offline. Actions are unavailable until the host reconnects.',
        ),
      Row(
        children: <Widget>[
          AleraBadge(
            label: state.label,
            tone: mobileAutomationBadgeTone(state.tone),
          ),
        ],
      ),
      if (automation.description.trim().isNotEmpty)
        Text(
          automation.description.trim(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
      if (!offline)
        MobileAutomationDetailActions(
          hostId: widget.hostId,
          automation: automation,
          actions: actions,
        ),
      if (!automation.isEditable)
        AleraNotice(
          message: automation.isCompleted
              ? 'Completed automations are read-only. Clone one to schedule it again.'
              : 'Restore this automation to edit it.',
        ),
      if (automation.attention case final attention?)
        AleraNotice(icon: AleraIcons.warning, message: attention.message),
      if (readiness != null && automation.isEditable)
        for (final issue in readiness.issues)
          AleraNotice(
            icon: issue.isError ? AleraIcons.warning : AleraIcons.info,
            message: issue.action == null
                ? issue.message
                : '${issue.message} ${issue.action}',
          ),
      MobileAutomationDetailFacts(automation: automation, names: names),
      if (supportsReuse && automation.reusePolicy.reuses)
        MobileAutomationBindingCard(
          hostId: widget.hostId,
          automation: automation,
          names: names,
          actions: actions,
          supportsReuse: supportsReuse,
        ),
      MobileAutomationDetailPrompt(prompt: automation.promptTemplate),
      MobileAutomationHistory(hostId: widget.hostId, detail: detail),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(automation.name, maxLines: 1, overflow: .ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: 'More Actions',
            icon: const Icon(AleraIcons.more),
            onPressed: offline
                ? null
                : () => unawaited(
                    showMobileAutomationMoreSheet(
                      context,
                      hostId: widget.hostId,
                      automation: automation,
                      actions: actions,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(provider.future),
          child: ListView(
            padding: AleraTokens.pagePadding,
            children: <Widget>[
              for (final (index, section) in sections.indexed) ...<Widget>[
                if (index > 0) const SizedBox(height: AleraTokens.spaceMd),
                section,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
