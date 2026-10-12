import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_composer_controller.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_destinations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the chosen destination still needs: a source branch for a worktree,
/// a folder for a project folder, or which conversation to continue when
/// the stored one is gone.
class const MobileAutomationDestinationFields({
  required final MobileAutomationComposerControllerProvider provider,
  required final String hostId,
  super.key,
}) extends ConsumerWidget {
  /// Whether [draft]'s destination has anything to show here. A conversation
  /// picked from Running Agents already names its tab.
  static bool needsFollowUp(AutomationDraft draft) =>
      switch (AutomationTargetChoice.of(draft)) {
        AutomationTargetChoice.projectWorktree ||
        AutomationTargetChoice.workspaceWorktree ||
        AutomationTargetChoice.projectCheckout => true,
        AutomationTargetChoice.existingTab =>
          (draft.field(.tabId) ?? '').isEmpty,
        AutomationTargetChoice.freshTab || null => false,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(provider.select((state) => state.draft));
    final names =
        ref.watch(mobileAutomationContextProvider(hostId)).value ??
        const MobileAutomationContext();
    final controller = ref.read(provider.notifier);
    void set(AutomationDraftField field, String? value) =>
        controller.update((current) => current.withTargetField(field, value));
    final branch = draft.field(.sourceBranch) ?? '';
    return switch (AutomationTargetChoice.of(draft)) {
      AutomationTargetChoice.projectWorktree => MobileAutomationBranchField(
        key: ValueKey<String?>(draft.field(.projectId)),
        hostId: hostId,
        projectId: draft.field(.projectId),
        value: branch,
        onChanged: (value) => set(.sourceBranch, value),
      ),
      AutomationTargetChoice.workspaceWorktree => MobileAutomationBranchField(
        key: ValueKey<String?>(draft.field(.parentWorkspaceId)),
        hostId: hostId,
        projectId: names.workspace(draft.field(.parentWorkspaceId))?.projectId,
        value: branch,
        onChanged: (value) => set(.sourceBranch, value),
      ),
      AutomationTargetChoice.projectCheckout => _ProjectFolderField(
        hostId: hostId,
        projectId: draft.field(.projectId),
        selected: draft.field(.hostId),
        names: names,
        onChanged: (value) => set(.hostId, value),
      ),
      AutomationTargetChoice.existingTab => _ConversationField(
        hostId: hostId,
        workspaceId: draft.field(.workspaceId),
        selected: draft.field(.tabId),
        onChanged: (tabId, conversationId) => controller.update(
          (current) => current
              .withTargetField(.tabId, tabId)
              .withTargetField(.conversationId, conversationId),
        ),
      ),
      AutomationTargetChoice.freshTab || null => const SizedBox.shrink(),
    };
  }
}

/// The branch each run's worktree starts from: the project's branches when
/// the runtime can list them, free text when it cannot.
class const MobileAutomationBranchField({
  required final String hostId,
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
        : ref.watch(mobileAutomationProjectBranchesProvider(hostId, projectId));
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
        const SizedBox(height: AleraTokens.spaceXs),
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
  required final String hostId,
  required final String? projectId,
  required final String? selected,
  required final MobileAutomationContext names,
  required final ValueChanged<String?> onChanged,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectId = this.projectId;
    if (projectId == null) return const SizedBox.shrink();
    final folders = ref.watch(
      mobileAutomationProjectFoldersProvider(hostId, projectId),
    );
    final entries = <AleraDropdownFieldEntry<String?>>[
      for (final folder
          in folders.value ?? const <({String hostId, String path})>[])
        AleraDropdownFieldEntry(
          value: folder.hostId,
          label: '${names.hostName(folder.hostId)}: ${folder.path}',
        ),
    ];
    final message = folders.hasError
        ? 'Could not load project folders. Check the connection and try again.'
        : folders.value?.isEmpty == true
        ? 'No registered folder for this project.'
        : null;
    return Column(
      crossAxisAlignment: .stretch,
      mainAxisSize: .min,
      children: <Widget>[
        AleraDropdownField<String?>(
          labelText: 'Project Folder',
          value: entries.any((entry) => entry.value == selected)
              ? selected
              : null,
          hintText: folders.isLoading ? 'Loading folders...' : 'Choose',
          entries: entries,
          onChanged: onChanged,
        ),
        if (message != null) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceXs),
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.error),
          ),
        ],
      ],
    );
  }
}

class const _ConversationField({
  required final String hostId,
  required final String? workspaceId,
  required final String? selected,
  required final void Function(String? tabId, String? conversationId) onChanged,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspaceId = this.workspaceId;
    if (workspaceId == null) return const SizedBox.shrink();
    final tabs =
        ref
            .watch(
              mobileAutomationConversationTabsProvider(hostId, workspaceId),
            )
            .value ??
        const [];
    return AleraDropdownField<String?>(
      labelText: 'Conversation',
      value: tabs.any((tab) => tab.id == selected) ? selected : null,
      hintText: tabs.isEmpty ? 'No conversation to continue' : 'Choose',
      entries: <AleraDropdownFieldEntry<String?>>[
        for (final tab in tabs)
          AleraDropdownFieldEntry(value: tab.id, label: tab.displayTitle),
      ],
      onChanged: (tabId) => onChanged(
        tabId,
        tabs.where((tab) => tab.id == tabId).firstOrNull?.agentNativeSessionId,
      ),
    );
  }
}
