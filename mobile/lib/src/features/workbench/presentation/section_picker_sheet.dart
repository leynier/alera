import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_view_prefs_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/mobile_section_header.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_section_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/section_selection_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_listing_tree.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showSectionPickerSheet(
  BuildContext context, {
  required String hostId,
  required WorkspaceSummary workspace,
  List<WorkspaceSummary> workspaces = const [],
  bool applyToTree = false,
  bool createMode = false,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  isDismissible: false,
  enableDrag: false,
  builder: (_) => _SectionPicker(
    hostId: hostId,
    workspace: workspace,
    extraWorkspaceIds: applyToTree
        ? workspaceDescendantIds(workspaces, workspace.id).toList()
        : const [],
    createMode: createMode,
  ),
);

class _SectionPicker extends ConsumerStatefulWidget {
  const _SectionPicker({
    required this.hostId,
    required this.workspace,
    required this.extraWorkspaceIds,
    required this.createMode,
  });
  final String hostId;
  final WorkspaceSummary workspace;
  final List<String> extraWorkspaceIds;
  final bool createMode;

  @override
  ConsumerState<_SectionPicker> createState() => _SectionPickerState();
}

class _SectionPickerState extends ConsumerState<_SectionPicker> {
  bool _createSelected = false;

  @override
  Widget build(BuildContext context) {
    final hostId = widget.hostId;
    final workspace = widget.workspace;
    final provider = sectionSelectionControllerProvider(
      hostId,
      workspace.id,
      workspace.sectionId,
    );
    final selection = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final current = selection.value;
    if (widget.createMode &&
        current != null &&
        !_createSelected &&
        current.selected != '__new__') {
      _createSelected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          controller.select('__new__');
        }
      });
    }
    return PopScope(
      canPop: current?.saving != true,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            padding: AleraTokens.contentPadding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.extraWorkspaceIds.isEmpty
                      ? 'Set Section'
                      : 'Set Section Tree',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AleraTokens.space16),
                if (current == null)
                  selection.when(
                    data: (_) => const SizedBox.shrink(),
                    loading: () => const LinearProgressIndicator(),
                    error: (error, _) => Column(
                      children: [
                        Text('$error'),
                        TextButton(
                          onPressed: () => ref.invalidate(provider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                else ...[
                  AleraDropdownField<String>(
                    value: current.selected,
                    enabled: !current.saving,
                    labelText: 'Section',
                    filterable: true,
                    filterHintText: 'Search Sections',
                    entries: [
                      const AleraDropdownFieldEntry(
                        value: '',
                        label: 'No Section',
                      ),
                      for (final section in current.sections)
                        AleraDropdownFieldEntry(
                          value: section.id,
                          label: section.name,
                        ),
                      const AleraDropdownFieldEntry(
                        value: '__new__',
                        label: 'New Section',
                      ),
                    ],
                    onChanged: controller.select,
                  ),
                  if (current.selected == '__new__') ...[
                    const SizedBox(height: AleraTokens.space12),
                    TextFormField(
                      initialValue: current.name,
                      enabled: !current.saving,
                      decoration: const InputDecoration(
                        labelText: 'Section Name',
                      ),
                      onChanged: controller.nameChanged,
                    ),
                  ],
                  if (current.error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AleraTokens.space12),
                      child: Text(
                        current.error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: AleraTokens.space16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: current?.saving == true
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    FilledButton(
                      onPressed: current == null || current.saving
                          ? null
                          : () async {
                              if (await controller.save(
                                    extraWorkspaceIds: widget.extraWorkspaceIds,
                                  ) &&
                                  context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                      child: Text(
                        current?.saving == true ? 'Saving...' : 'Save',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showSectionActionsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  required WorkspaceSectionSummary section,
}) async {
  final delete = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: ListTile(
        title: const Text('Delete Section'),
        onTap: () => Navigator.pop(context, true),
      ),
    ),
  );
  if (delete != true || !context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete Section?'),
      content: Text(
        'Delete "${section.name}"? Its workspaces will be preserved and moved to Others.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete Section'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref
        .read(workspaceListControllerProvider(hostId).notifier)
        .removeSection(section.id);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete section: $error')),
      );
    }
  }
}

class MobileCustomSectionHeader extends ConsumerWidget {
  const MobileCustomSectionHeader({
    super.key,
    required this.hostId,
    required this.row,
    required this.supportsSections,
  });
  final String hostId;
  final MobileCustomSectionHeaderRow row;
  final bool supportsSections;
  @override
  Widget build(BuildContext context, WidgetRef ref) => MobileSectionHeader(
    label: row.section?.name ?? 'Others',
    icon: AleraIcons.folder,
    count: row.count,
    collapsed: row.collapsed,
    onToggle: () => ref
        .read(mobileViewPrefsControllerProvider(hostId).notifier)
        .toggleSectionCollapsed(row.section?.id),
    onLongPress: row.section == null || !supportsSections
        ? null
        : () => showSectionActionsSheet(
            context,
            ref,
            hostId: hostId,
            section: row.section!,
          ),
  );
}
