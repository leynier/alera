import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_authoring_controller.dart';
import 'package:alera_mobile/src/features/automations/application/mobile_automation_context.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_draft.dart';
import 'package:alera_mobile/src/features/automations/domain/automation_models.dart';
import 'package:alera_mobile/src/features/automations/presentation/mobile_automation_lines.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The execution target type is never chosen for the user: no option starts
/// selected, whichever screen opened the flow.
class const MobileWhereStep({
  required final MobileAutomationAuthoringControllerProvider provider,
  required final String hostId,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final contextValue = ref.watch(mobileAutomationContextProvider(hostId));
    final names = contextValue.value;
    if (names == null) {
      return contextValue.hasError
          ? Text('Workspaces are unavailable: ${contextValue.error}')
          : const Center(child: CircularProgressIndicator());
    }
    final draft = state.draft;
    final theme = Theme.of(context);
    final origin = names.workspace(draft.originWorkspaceId);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        if (origin != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.spaceMd),
            child: Text(
              'Created from ${origin.name}. This shows the automation in that workspace; it does not choose where it runs.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
        Text('Where Should It Run?', style: theme.textTheme.titleMedium),
        for (final type in AutomationTargetType.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            selected: draft.targetType == type,
            leading: Icon(
              draft.targetType == type ? AleraIcons.check : AleraIcons.circle,
            ),
            title: Text(type.label),
            subtitle: Text(mobileTargetDescription(type)),
            onTap: () => controller.update(
              (current) =>
                  chooseMobileAutomationTargetType(current, type, names),
            ),
          ),
        if (draft.targetType != null)
          _MobileTargetFields(
            provider: provider,
            hostId: hostId,
            draft: draft,
            names: names,
          ),
      ],
    );
  }
}

class const _MobileTargetFields({
  required final MobileAutomationAuthoringControllerProvider provider,
  required final String hostId,
  required final AutomationDraft draft,
  required final MobileAutomationContext names,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(provider.notifier);
    final type = draft.targetType!;
    void set(AutomationDraftField field, String? value) =>
        controller.update((current) => current.withTargetField(field, value));
    Widget picker(
      AutomationDraftField field,
      String label,
      List<AleraDropdownFieldEntry<String?>> entries, {
      ValueChanged<String?>? onChanged,
    }) {
      final value = draft.field(field);
      return Padding(
        padding: const EdgeInsets.only(top: AleraTokens.spaceMd),
        child: Row(
          children: <Widget>[
            Expanded(
              child: AleraDropdownField<String?>(
                labelText: label,
                hintText: 'Choose',
                value: entries.any((entry) => entry.value == value)
                    ? value
                    : null,
                filterable: entries.length > 8,
                entries: entries,
                onChanged: onChanged ?? (next) => set(field, next),
              ),
            ),
            if (draft.fromContext.contains(field)) ...<Widget>[
              const SizedBox(width: AleraTokens.spaceSm),
              const AleraBadge(label: 'From Context'),
            ],
          ],
        ),
      );
    }

    final workspaces = <AleraDropdownFieldEntry<String?>>[
      for (final workspace in names.workspaces)
        if (type != AutomationTargetType.managedWorkspace ||
            names.isGitProject(workspace.projectId))
          AleraDropdownFieldEntry(
            value: workspace.id,
            label:
                '${names.projectName(workspace.projectId)} / ${workspace.name}',
          ),
    ];
    final children = <Widget>[];
    switch (type) {
      case AutomationTargetType.freshTab:
        children.add(picker(.workspaceId, 'Workspace', workspaces));
      case AutomationTargetType.managedWorkspace:
        children.add(
          picker(
            .workspaceId,
            'Source Workspace',
            workspaces,
            onChanged: (value) => controller.update((current) {
              var next = current.withTargetField(.workspaceId, value);
              final branch = names.workspace(value)?.branch?.trim();
              if (branch != null && branch.isNotEmpty) {
                next = next.withTargetField(.sourceBranch, branch);
                next = next.copyWith(
                  fromContext: <AutomationDraftField>{
                    ...next.fromContext,
                    .sourceBranch,
                  },
                );
              }
              return next;
            }),
          ),
        );
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.spaceMd),
            child: _BranchField(
              key: ValueKey<String?>(draft.field(.workspaceId)),
              value: draft.field(.sourceBranch) ?? '',
              onChanged: (value) => set(.sourceBranch, value),
            ),
          ),
        );
      case AutomationTargetType.projectWorktree:
        children.add(
          picker(.projectId, 'Project', <AleraDropdownFieldEntry<String?>>[
            for (final project in names.projects)
              if (names.isGitProject(project.id))
                AleraDropdownFieldEntry(value: project.id, label: project.name),
          ]),
        );
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.spaceMd),
            child: _BranchField(
              key: ValueKey<String?>(draft.field(.projectId)),
              value: draft.field(.sourceBranch) ?? '',
              onChanged: (value) => set(.sourceBranch, value),
            ),
          ),
        );
      case AutomationTargetType.projectCheckout:
        final projectId = draft.field(.projectId);
        children.add(
          picker(
            .projectId,
            'Project',
            <AleraDropdownFieldEntry<String?>>[
              for (final project in names.projects)
                AleraDropdownFieldEntry(value: project.id, label: project.name),
            ],
            onChanged: (value) => controller.update(
              (current) => current
                  .withTargetField(.projectId, value)
                  .withTargetField(.hostId, null),
            ),
          ),
        );
        if (projectId != null) {
          final checkouts = ref.watch(
            mobileAutomationProjectFoldersProvider(hostId, projectId),
          );
          children.add(
            picker(
              .hostId,
              'Project Folder',
              <AleraDropdownFieldEntry<String?>>[
                for (final checkout
                    in checkouts.value ??
                        const <({String hostId, String path})>[])
                  AleraDropdownFieldEntry(
                    value: checkout.hostId,
                    label:
                        '${names.hostName(checkout.hostId)}: ${checkout.path}',
                  ),
              ],
            ),
          );
        }
      case AutomationTargetType.existingTab:
        final workspaceId = draft.field(.workspaceId);
        children.add(
          picker(
            .workspaceId,
            'Workspace',
            workspaces,
            onChanged: (value) => controller.update(
              (current) => current
                  .withTargetField(.workspaceId, value)
                  .withTargetField(.tabId, null)
                  .withTargetField(.conversationId, null),
            ),
          ),
        );
        if (workspaceId != null) {
          final tabs =
              ref
                  .watch(
                    mobileAutomationConversationTabsProvider(
                      hostId,
                      workspaceId,
                    ),
                  )
                  .value ??
              const [];
          children.add(
            tabs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(top: AleraTokens.spaceMd),
                    child: Text(
                      'This workspace has no agent tab whose conversation Alera can resume.',
                    ),
                  )
                : picker(
                    .tabId,
                    'Agent Tab',
                    <AleraDropdownFieldEntry<String?>>[
                      for (final tab in tabs)
                        AleraDropdownFieldEntry(
                          value: tab.id,
                          label: tab.displayTitle,
                        ),
                    ],
                    onChanged: (value) => controller.update((current) {
                      final tab = tabs
                          .where((item) => item.id == value)
                          .firstOrNull;
                      return current
                          .withTargetField(.tabId, value)
                          .withTargetField(
                            .conversationId,
                            tab?.agentNativeSessionId,
                          );
                    }),
                  ),
          );
        }
    }
    if (type != AutomationTargetType.existingTab) {
      children.add(
        picker(
          .agentProfileId,
          'Agent Profile',
          <AleraDropdownFieldEntry<String?>>[
            for (final profile in names.profiles)
              AleraDropdownFieldEntry(value: profile.id, label: profile.name),
          ],
        ),
      );
    }
    return Column(crossAxisAlignment: .stretch, children: children);
  }
}

class _BranchField extends StatefulWidget {
  const _BranchField({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_BranchField> createState() => _BranchFieldState();
}

class _BranchFieldState extends State<_BranchField> {
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
    onChanged: widget.onChanged,
  );
}
