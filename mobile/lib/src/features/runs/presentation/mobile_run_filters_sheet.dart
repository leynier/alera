import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Search, group and workspace filters of the runs list. The runtime filters,
/// so every page stays full.
Future<void> showMobileRunFilters(BuildContext context, String hostId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MobileRunFiltersSheet(hostId: hostId),
    );

class const MobileRunFiltersSheet({super.key, required final String hostId})
    extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mobileRunListControllerProvider(hostId));
    final controller = ref.read(
      mobileRunListControllerProvider(hostId).notifier,
    );
    final workspaces =
        ref.watch(mobileRunWorkspacesProvider(hostId)).value ?? const [];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AleraTokens.space16,
          right: AleraTokens.space16,
          top: AleraTokens.space16,
          bottom: AleraTokens.space16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraSearchField(
              hintText: 'Search Runs',
              initialValue: state.search,
              debounce: AleraTokens.durationMid,
              onChanged: controller.setSearch,
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            Wrap(
              spacing: AleraTokens.space8,
              runSpacing: AleraTokens.space8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('All'),
                  selected: state.bucket == null,
                  onSelected: (_) => controller.setBucket(null),
                ),
                for (final bucket in RunBucket.values)
                  ChoiceChip(
                    label: Text(bucket.label),
                    selected: state.bucket == bucket,
                    onSelected: (_) => controller.setBucket(bucket),
                  ),
              ],
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            AleraDropdownField<String?>(
              labelText: 'Workspace',
              value: state.workspaceId,
              filterable: true,
              entries: <AleraDropdownFieldEntry<String?>>[
                const AleraDropdownFieldEntry(
                  value: null,
                  label: 'All Workspaces',
                ),
                for (final workspace in workspaces)
                  AleraDropdownFieldEntry(
                    value: workspace.id,
                    label: workspace.name,
                  ),
              ],
              onChanged: controller.setWorkspace,
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            TextButton(
              onPressed: controller.clear,
              child: const Text('Clear Filters'),
            ),
          ],
        ),
      ),
    );
  }
}
