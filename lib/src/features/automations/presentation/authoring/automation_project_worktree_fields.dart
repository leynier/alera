import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/automations/application/automation_authoring_controller.dart';
import 'package:alera/src/features/automations/application/automation_project_branches.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera/src/features/automations/domain/automation_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A field the entry context filled, with the badge that says so.
class const AutomationContextMarked({
  required final bool fromContext,
  required final Widget child,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!fromContext) return child;
    return Row(
      children: <Widget>[
        Expanded(child: child),
        const SizedBox(width: AleraTokens.space8),
        const AleraBadge(label: 'From Context'),
      ],
    );
  }
}

/// Project and source branch of a target that creates a new workspace and
/// worktree on every run. The branch list is the one Create Workspace shows,
/// and the project's default source branch is preselected.
class const AutomationProjectWorktreeFields({
  required final AutomationAuthoringControllerProvider provider,
  required final AutomationDraft draft,
  required final AutomationWorkbenchContext names,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(provider.notifier);
    final projectId = draft.field(.projectId);
    final projects = <AleraDropdownFieldEntry<String?>>[
      for (final project in names.projects)
        if (project.isGitRepository && !project.isRemoteOnly)
          AleraDropdownFieldEntry(value: project.id, label: project.name),
    ];
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AutomationContextMarked(
          fromContext: draft.fromContext.contains(
            AutomationDraftField.projectId,
          ),
          child: AleraDropdownField<String?>(
            labelText: 'Project',
            value: projects.any((entry) => entry.value == projectId)
                ? projectId
                : null,
            hintText: 'Choose',
            filterable: projects.length > 8,
            filterHintText: 'Search',
            entries: projects,
            onChanged: (value) => controller.update(
              (current) => current
                  .withTargetField(.projectId, value)
                  .withTargetField(.sourceBranch, null),
            ),
          ),
        ),
        if (projectId != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space12),
          _SourceBranchPicker(
            key: ValueKey<String>(projectId),
            provider: provider,
            draft: draft,
            projectId: projectId,
          ),
        ],
      ],
    );
  }
}

class const _SourceBranchPicker({
  required final AutomationAuthoringControllerProvider provider,
  required final AutomationDraft draft,
  required final String projectId,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(provider.notifier);
    final branchesProvider = automationProjectBranchesProvider(projectId);
    final branches = ref.watch(branchesProvider);
    final value = draft.field(.sourceBranch);
    if (branches.value?.initial case final initial?
        when (value ?? '').isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final current = ref.read(provider).draft;
        if (current.field(.projectId) != projectId ||
            (current.field(.sourceBranch) ?? '').isNotEmpty) {
          return;
        }
        controller.update(
          (draft) => draft.withTargetField(.sourceBranch, initial),
        );
      });
    }
    final names = branches.value?.branches ?? const <String>[];
    final Widget field;
    if (branches.isLoading && !branches.hasValue) {
      field = AleraDropdownField<String?>(
        labelText: 'Source Branch',
        value: null,
        hintText: 'Loading branches...',
        entries: const <AleraDropdownFieldEntry<String?>>[],
        enabled: false,
        onChanged: (_) {},
      );
    } else if (names.isEmpty) {
      field = _ManualBranchField(
        value: value ?? '',
        helperText: branches.hasError
            ? 'Could not load branches. Type the branch to start from.'
            : null,
        onChanged: (next) => controller.update(
          (current) => current.withTargetField(.sourceBranch, next),
        ),
      );
    } else {
      final entries = <AleraDropdownFieldEntry<String?>>[
        if (value != null && !names.contains(value))
          AleraDropdownFieldEntry(value: value, label: value),
        for (final branch in names)
          AleraDropdownFieldEntry(value: branch, label: branch),
      ];
      field = AleraDropdownField<String?>(
        labelText: 'Source Branch',
        value: value,
        hintText: 'Choose',
        filterable: entries.length > 8,
        filterHintText: 'Search branches',
        entries: entries,
        onChanged: (next) => controller.update(
          (current) => current.withTargetField(.sourceBranch, next),
        ),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AutomationContextMarked(
          fromContext: draft.fromContext.contains(
            AutomationDraftField.sourceBranch,
          ),
          child: field,
        ),
        const SizedBox(height: AleraTokens.space6),
        Text(
          'Each run creates a new branch from this one in its own worktree.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AleraTokens.foregroundMuted),
        ),
      ],
    );
  }
}

class _ManualBranchField extends StatefulWidget {
  const _ManualBranchField({
    required this.value,
    required this.onChanged,
    this.helperText,
  });

  final String value;
  final String? helperText;
  final ValueChanged<String> onChanged;

  @override
  State<_ManualBranchField> createState() => _ManualBranchFieldState();
}

class _ManualBranchFieldState extends State<_ManualBranchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AleraTextField(
    controller: _controller,
    labelText: 'Source Branch',
    hintText: 'e.g. main',
    errorText: widget.helperText,
    onChanged: widget.onChanged,
  );
}
