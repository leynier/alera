import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/automations/application/automation_providers.dart';
import 'package:alera/src/features/automations/presentation/detail/automation_activity_tab.dart';
import 'package:alera/src/features/automations/presentation/detail/automation_binding_card.dart';
import 'package:alera/src/features/automations/presentation/detail/automation_detail_facts.dart';
import 'package:alera/src/features/automations/presentation/detail/automation_detail_header.dart';
import 'package:alera/src/features/automations/presentation/detail/automation_detail_prompt.dart';
import 'package:alera/src/features/automations/presentation/detail/automation_runs_tab.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _DetailTab(final String label) {
  runs('Runs'),
  activity('Activity'),
}

/// One automation: header and actions, its problems, the facts, the reuse
/// binding, the prompt, then its runs or activity.
class AutomationDetailView extends ConsumerStatefulWidget {
  const AutomationDetailView({
    super.key,
    required this.automation,
    this.selectedRunId,
    this.onBack,
  });

  final AutomationRecord automation;
  final String? selectedRunId;
  final VoidCallback? onBack;

  @override
  ConsumerState<AutomationDetailView> createState() =>
      _AutomationDetailViewState();
}

class _AutomationDetailViewState extends ConsumerState<AutomationDetailView> {
  _DetailTab _tab = _DetailTab.runs;

  @override
  void didUpdateWidget(AutomationDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedRunId != null &&
        widget.selectedRunId != oldWidget.selectedRunId) {
      _tab = _DetailTab.runs;
    }
  }

  @override
  Widget build(BuildContext context) {
    final automation = widget.automation;
    final provider = automationDetailControllerProvider(automation.id);
    final detail = ref.watch(provider);
    final value = detail.value;
    final readiness = automation.readiness;
    final notices = <Widget>[
      if (!automation.isEditable)
        AleraInlineNotice(
          message: automation.isCompleted
              ? 'Completed automations are read-only. Clone one to schedule it again.'
              : 'Restore this automation to edit it.',
        ),
      if (automation.attention case final attention?)
        AleraInlineNotice(tone: .warning, message: attention.message),
      if (readiness != null && automation.isEditable)
        for (final issue in readiness.issues)
          AleraInlineNotice(
            tone: issue.isError ? .error : .warning,
            message: issue.message,
          ),
    ];
    final sections = <Widget>[
      AutomationDetailHeader(automation: automation, onBack: widget.onBack),
      ...notices,
      AutomationDetailFacts(automation: automation),
      AutomationBindingCard(automation: automation),
      AutomationDetailPrompt(prompt: automation.promptTemplate),
      Align(
        alignment: Alignment.centerLeft,
        child: AleraSegmentedButton<_DetailTab>(
          selected: _tab,
          segments: <ButtonSegment<_DetailTab>>[
            for (final tab in _DetailTab.values)
              ButtonSegment(value: tab, label: Text(tab.label)),
          ],
          onSelectionChanged: (tab) => setState(() => _tab = tab),
        ),
      ),
      if (value == null)
        detail.hasError
            ? AleraEmptyState(
                icon: AleraIcons.error,
                title: 'Automation Unavailable',
                message: automationErrorMessage(detail.error),
                action: FilledButton(
                  onPressed: () => ref.invalidate(provider),
                  child: const Text('Retry'),
                ),
              )
            : const AleraEmptyState(message: 'Loading runs.', loading: true)
      else
        switch (_tab) {
          _DetailTab.runs => AutomationRunsTab(
            automation: automation,
            detail: value,
            selectedRunId: widget.selectedRunId,
          ),
          _DetailTab.activity => AutomationActivityTab(events: value.audit),
        },
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space24,
        AleraTokens.space16,
        AleraTokens.space24,
        AleraTokens.space24,
      ),
      children: <Widget>[
        for (final (index, section) in sections.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: AleraTokens.space12),
          section,
        ],
      ],
    );
  }
}
