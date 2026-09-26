import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/orchestration/domain/task_inspection.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_read_state.dart';
import 'package:flutter/material.dart';

class RunTaskInspector extends StatelessWidget {
  const RunTaskInspector({
    super.key,
    required this.task,
    required this.history,
    required this.onBack,
    this.onOpenWorkspace,
    this.onOpenTerminal,
    this.onOpenDiff,
    required this.footer,
  });
  final TaskInspection task;
  final List<TaskHistoryEntry> history;
  final VoidCallback onBack;
  final VoidCallback? onOpenWorkspace;
  final VoidCallback? onOpenTerminal;
  final VoidCallback? onOpenDiff;
  final Widget footer;

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: PageStorageKey('task-inspection:${task.taskId}'),
    padding: const EdgeInsets.all(AleraTokens.space16),
    itemCount: history.length + 2,
    itemBuilder: (context, index) {
      if (index == 0) return _content(context);
      if (index == history.length + 1) return footer;
      final event = history[index - 1];
      return Container(
        key: ValueKey('${event.kind}:${event.id}'),
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${event.kind == 'attempt' ? 'Attempt' : 'Event'} · ${runBoardStatusLabel(event.status)}',
            ),
            SelectableText(
              event.occurredAt,
              style: AleraTokens.monoCompactStyle,
            ),
            if (event.summary != null) SelectableText(event.summary!),
          ],
        ),
      );
    },
  );

  Widget _content(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onBack,
          icon: const Icon(AleraIcons.back),
          label: const Text('Back to Run'),
        ),
      ),
      const SizedBox(height: AleraTokens.space16),
      Text(task.title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: AleraTokens.space8),
      Align(
        alignment: Alignment.centerLeft,
        child: AleraBadge(
          label: runBoardStatusLabel(task.status),
          foregroundColor: runBoardStatusColor(task.status),
        ),
      ),
      const SizedBox(height: AleraTokens.space12),
      SelectableText(task.taskId, style: AleraTokens.monoCompactStyle),
      const SizedBox(height: AleraTokens.space16),
      SelectableText(task.description),
      if (task.descriptionTruncated)
        const Text('The task description is truncated.'),
      const SizedBox(height: AleraTokens.space16),
      Wrap(
        spacing: AleraTokens.space8,
        runSpacing: AleraTokens.space8,
        children: [
          OutlinedButton(
            onPressed: onOpenWorkspace,
            child: const Text('Open Workspace'),
          ),
          OutlinedButton(
            onPressed: onOpenTerminal,
            child: const Text('Open Terminal'),
          ),
          OutlinedButton(onPressed: onOpenDiff, child: const Text('Open Diff')),
        ],
      ),
      const SizedBox(height: AleraTokens.space8),
      const Text(
        'Open Diff shows the current workspace changes, not an immutable task result.',
      ),
      _field(context, 'Profile', task.profile ?? 'Not recorded'),
      _field(
        context,
        'Worktree',
        task.workspacePath ?? task.workspaceName ?? 'Unavailable',
      ),
      _field(context, 'Branch', task.branch ?? 'Not recorded'),
      _field(
        context,
        'Base SHA',
        task.baseSha ?? 'Not recorded for this attempt',
      ),
      _field(
        context,
        'Dependencies',
        task.dependencies.isEmpty
            ? 'None recorded'
            : task.dependencies.join('\n'),
      ),
      if (task.dependenciesTruncated)
        const Text('The dependency list is incomplete.'),
      if (onOpenWorkspace == null)
        const Text('The execution workspace is unavailable on this host.'),
      if (onOpenTerminal == null)
        const Text('No matching terminal is currently available.'),
      _section(context, 'Result'),
      SelectableText(
        task.result.summary ??
            task.result.preview ??
            'No result has been submitted.',
      ),
      if (task.result.completionKind != null)
        _field(context, 'Completion Kind', task.result.completionKind!),
      if (task.result.truncated) const Text('The result preview is truncated.'),
      _section(context, 'Artifacts'),
      if (task.result.artifacts.isEmpty) const Text('No artifacts recorded.'),
      for (final artifact in task.result.artifacts) _entry(artifact),
      _section(context, 'Validation'),
      const Text(
        'Worker-reported evidence. This is not an independent review or a human gate approval.',
      ),
      if (task.result.validation.isEmpty)
        const Text('No validation evidence recorded.'),
      for (final validation in task.result.validation) _entry(validation),
      _section(context, 'History'),
      if (history.isEmpty) const Text('No attempts or task events recorded.'),
    ],
  );

  Widget _field(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: AleraTokens.space12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AleraTokens.space4),
        SelectableText(value, style: AleraTokens.monoStyle),
      ],
    ),
  );
  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(
      top: AleraTokens.space24,
      bottom: AleraTokens.space8,
    ),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
  Widget _entry(String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
    child: SelectableText(value, style: AleraTokens.monoStyle),
  );
}
