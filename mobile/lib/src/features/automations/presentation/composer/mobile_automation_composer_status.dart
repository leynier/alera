import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_key_value_row.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The next scheduled times and what the runtime thinks of the draft, both
/// kept current while the user edits.
class const MobileAutomationComposerStatus({
  required final MobileAutomationComposerControllerProvider provider,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    final theme = Theme.of(context);
    final preview = state.preview;
    final occurrences = preview == null || preview.errors.isNotEmpty
        ? null
        : preview.occurrences
              .take(3)
              .map(automationOccurrenceLabel)
              .join(' · ');
    final (tone, summary) = _readinessSummary(state);
    final issues = state.draft.localProblems.isEmpty
        ? state.readiness?.issues ?? const <AutomationReadinessIssue>[]
        : const <AutomationReadinessIssue>[];
    final scheduleError = preview?.errors.firstOrNull?.message;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraKeyValueRow(
          label: 'Next Runs',
          value:
              scheduleError ??
              (occurrences == null || occurrences.isEmpty
                  ? 'No upcoming runs to show.'
                  : occurrences),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: AleraTokens.keyColumnWidth + AleraTokens.space8,
                child: Text(
                  'Readiness',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
              AleraStatusDot(active: true, color: tone),
              const SizedBox(width: AleraTokens.space6),
              Expanded(child: Text(summary, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
        for (final issue in issues) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          AleraNotice(
            icon: issue.isError ? AleraIcons.warning : AleraIcons.info,
            message: issue.action == null
                ? issue.message
                : '${issue.message} ${issue.action}',
          ),
        ],
        if (state.error case final error?) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          AleraNotice(icon: AleraIcons.warning, message: error),
        ],
      ],
    );
  }
}

(Color, String) _readinessSummary(MobileAutomationComposerState state) {
  final problems = state.draft.localProblems;
  if (problems.isNotEmpty) {
    return state.showErrors
        ? (AleraTokens.error, problems.values.first)
        : (
            AleraTokens.foregroundFaint,
            'Checked once the prompt, destination and agent are set.',
          );
  }
  if (state.checking) return (AleraTokens.info, 'Checking...');
  final readiness = state.readiness;
  if (readiness == null) {
    return (AleraTokens.foregroundFaint, 'Checked when you save.');
  }
  final errors = readiness.errors.length;
  if (errors > 0) {
    return (
      AleraTokens.error,
      errors == 1 ? '1 problem to fix' : '$errors problems to fix',
    );
  }
  return readiness.warnings.isEmpty
      ? (AleraTokens.success, 'Ready')
      : (AleraTokens.warning, 'Ready, with warnings');
}
