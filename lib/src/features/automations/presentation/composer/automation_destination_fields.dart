import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/automations/application/automation_composer_controller.dart';
import 'package:alera/src/features/automations/application/automation_project_branches.dart';
import 'package:alera/src/features/automations/application/automation_project_checkouts.dart';
import 'package:alera/src/features/automations/application/automation_workbench_context.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the chosen destination still needs: a source branch for a worktree,
/// a folder for a project folder, or which conversation to continue.
class const AutomationDestinationFields({
  required final AutomationComposerControllerProvider provider,
  super.key,
}) extends ConsumerWidget {
  /// Whether [choice] has anything to show here.
  static bool needsFollowUp(AutomationTargetChoice? choice) => switch (choice) {
    AutomationTargetChoice.projectWorktree ||
    AutomationTargetChoice.workspaceWorktree ||
    AutomationTargetChoice.projectCheckout ||
    AutomationTargetChoice.existingTab => true,
    AutomationTargetChoice.freshTab || null => false,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(provider.select((state) => state.draft));
    final names = ref.watch(automationWorkbenchContextProvider);
    final controller = ref.read(provider.notifier);
    void set(AutomationDraftField field, String? value) =>
        controller.update((current) => current.withTargetField(field, value));
    final branch = draft.field(.sourceBranch) ?? '';
    return switch (AutomationTargetChoice.of(draft)) {
      AutomationTargetChoice.projectWorktree => AutomationSourceBranchField(
        key: ValueKey<String?>(draft.field(.projectId)),
        projectId: draft.field(.projectId),
        value: branch,
        onChanged: (value) => set(.sourceBranch, value),
      ),
      AutomationTargetChoice.workspaceWorktree => AutomationSourceBranchField(
        key: ValueKey<String?>(draft.field(.parentWorkspaceId)),
        projectId: names.workspace(draft.field(.parentWorkspaceId))?.projectId,
        value: branch,
        onChanged: (value) => set(.sourceBranch, value),
      ),
      AutomationTargetChoice.projectCheckout => _ProjectFolderField(
        projectId: draft.field(.projectId),
        hostId: draft.field(.hostId),
        names: names,
        onChanged: (value) => set(.hostId, value),
      ),
      AutomationTargetChoice.existingTab => AleraDropdownField<String?>(
        labelText: 'Conversation',
        value: draft.field(.tabId),
        hintText: 'Choose',
        entries: <AleraDropdownFieldEntry<String?>>[
          for (final tab in names.conversationTabs(
            draft.field(.workspaceId) ?? '',
          ))
            AleraDropdownFieldEntry(value: tab.id, label: tab.title),
        ],
        onChanged: (tabId) => controller.update((current) {
          final tab = names
              .conversationTabs(current.field(.workspaceId) ?? '')
              .where((item) => item.id == tabId)
              .firstOrNull;
          return current
              .withTargetField(.tabId, tabId)
              .withTargetField(
                .conversationId,
                tab == null ? null : automationConversationId(tab),
              );
        }),
      ),
      AutomationTargetChoice.freshTab || null => const SizedBox.shrink(),
    };
  }
}

/// The branch each run's worktree starts from: the project's branches when
/// Alera can list them, free text when it cannot.
class const AutomationSourceBranchField({
  required final String? projectId,
  required final String value,
  required final ValueChanged<String?> onChanged,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = this.projectId;
    final branches = projectId == null
        ? null
        : ref.watch(automationProjectBranchesProvider(projectId));
    final listed = branches?.value?.branches ?? const <String>[];
    final Widget field;
    if (branches != null && branches.isLoading && !branches.hasValue) {
      field = AleraDropdownField<String?>(
        labelText: 'Source Branch',
        value: null,
        hintText: 'Loading branches...',
        entries: const <AleraDropdownFieldEntry<String?>>[],
        enabled: false,
        onChanged: (_) {},
      );
    } else if (listed.isEmpty) {
      field = _ManualBranchField(value: value, onChanged: onChanged);
    } else {
      final entries = <AleraDropdownFieldEntry<String?>>[
        if (value.isNotEmpty && !listed.contains(value))
          AleraDropdownFieldEntry(value: value, label: value),
        for (final branch in listed)
          AleraDropdownFieldEntry(value: branch, label: branch),
      ];
      field = AleraDropdownField<String?>(
        labelText: 'Source Branch',
        value: value.isEmpty ? null : value,
        hintText: 'Choose',
        filterable: entries.length > 8,
        filterHintText: 'Search Branches',
        entries: entries,
        onChanged: onChanged,
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        field,
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
  const _ManualBranchField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String?> onChanged;

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
    hintText: 'Type the branch to start from, for example main.',
    autocorrect: false,
    enableSuggestions: false,
    onChanged: widget.onChanged,
  );
}

class const _ProjectFolderField({
  required final String? projectId,
  required final String? hostId,
  required final AutomationWorkbenchContext names,
  required final ValueChanged<String?> onChanged,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = this.projectId;
    if (projectId == null) return const SizedBox.shrink();
    final folders = ref.watch(automationProjectCheckoutsProvider(projectId));
    final entries = <AleraDropdownFieldEntry<String?>>[
      for (final folder
          in folders.value ?? const <({String hostId, String path})>[])
        AleraDropdownFieldEntry(
          value: folder.hostId,
          label: '${names.hostName(folder.hostId)}: ${folder.path}',
        ),
    ];
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        AleraDropdownField<String?>(
          labelText: 'Project Folder',
          value: entries.any((entry) => entry.value == hostId) ? hostId : null,
          hintText: folders.isLoading ? 'Loading folders...' : 'Choose',
          entries: entries,
          onChanged: onChanged,
        ),
        if (folders.hasError) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          Text(
            'Could not load project folders. Check the runtime connection and try again.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.error),
          ),
        ],
      ],
    );
  }
}
