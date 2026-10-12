import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/features/automations/application/automation_composer_controller.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The next scheduled times and what the runtime thinks of the draft, both
/// kept current while the user edits.
class const AutomationComposerStatus({
  required final AutomationComposerControllerProvider provider,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
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
    Widget line(String label, Widget value) => Row(
      crossAxisAlignment: .start,
      children: <Widget>[
        SizedBox(
          width: AleraTokens.keyValueLabelWidth,
          child: Text(label, style: muted),
        ),
        Expanded(child: value),
      ],
    );
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        line(
          'Next Runs',
          Text(
            preview?.errors.firstOrNull?.message ??
                (occurrences == null || occurrences.isEmpty
                    ? 'No upcoming runs to show.'
                    : occurrences),
            style: preview?.errors.isNotEmpty == true
                ? theme.textTheme.bodySmall?.copyWith(color: AleraTokens.error)
                : theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: AleraTokens.space6),
        line(
          'Readiness',
          Row(
            children: <Widget>[
              AleraStatusDot(active: true, color: tone),
              const SizedBox(width: AleraTokens.space6),
              Expanded(child: Text(summary, style: theme.textTheme.bodySmall)),
            ],
          ),
        ),
        for (final issue in issues) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          AleraInlineNotice(
            tone: issue.isError ? .error : .warning,
            message: issue.message,
          ),
        ],
        if (state.error case final error?) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          AleraInlineNotice(tone: .error, message: error),
        ],
      ],
    );
  }
}

(Color, String) _readinessSummary(AutomationComposerState state) {
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
