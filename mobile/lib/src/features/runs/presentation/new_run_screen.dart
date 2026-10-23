import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/core/errors/action_failure_feedback.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_new_run_form.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/new_run_models.dart';
import 'package:alera_mobile/src/features/runs/domain/run_error_messages.dart';
import 'package:alera_mobile/src/features/runs/domain/run_models.dart';
import 'package:alera_mobile/src/features/runs/presentation/run_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Starts a run: objective, workspace, isolation, template and profiles.
/// Opens the new run once the runtime created it.
class const NewRunScreen({
  super.key,
  required final String hostId,
  final String? workspaceId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final formProvider = mobileNewRunFormProvider(
      hostId,
      workspaceId: workspaceId,
    );
    final draft = ref.watch(formProvider);
    final form = ref.read(formProvider.notifier);
    final workspaces =
        ref.watch(mobileRunWorkspacesProvider(hostId)).value ?? const [];
    final profiles =
        ref.watch(mobileRunAgentProfilesProvider(hostId)).value ?? const [];
    final isolated = draft.isolation == RunIsolation.isolated;
    final catalog = isolated
        ? ref.watch(
            mobileRecipeCatalogProvider(hostId, workspaceId: draft.workspaceId),
          )
        : null;
    final recipes = catalog?.value?.usable ?? const <RecipeSummary>[];
    final selectedRecipe = draft.recipe ?? RecipeSource.freeform;
    final recipeEntries = <AleraDropdownFieldEntry<String>>[
      if (!recipes.any((r) => r.source.key == RecipeSource.freeform.key))
        const AleraDropdownFieldEntry(
          value: 'builtIn:freeform',
          label: 'Freeform (Built-in)',
        ),
      for (final recipe in recipes)
        AleraDropdownFieldEntry(value: recipe.source.key, label: recipe.label),
    ];
    final source = isolated && draft.workspaceId != null
        ? ref.watch(mobileRunSourceProvider(hostId, draft.workspaceId!))
        : null;
    final profileEntries = <AleraDropdownFieldEntry<String?>>[
      for (final profile in profiles)
        AleraDropdownFieldEntry(value: profile.id, label: profile.name),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Run'),
        actions: <Widget>[
          TextButton(
            onPressed: draft.canSubmit
                ? () => unawaited(_create(context, form))
                : null,
            child: draft.submitting
                ? const SizedBox.square(
                    dimension: AleraTokens.iconSm,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: AleraTokens.pagePadding,
          children: <Widget>[
            const AleraSectionHeader(label: 'Objective'),
            TextFormField(
              key: const Key('new-run-objective'),
              initialValue: draft.objective,
              minLines: 2,
              maxLines: 6,
              onChanged: form.setObjective,
              decoration: const InputDecoration(
                hintText: 'What should the agents get done?',
              ),
            ),
            const AleraSectionHeader(label: 'Workspace'),
            AleraDropdownField<String?>(
              value: draft.workspaceId,
              hintText: 'Choose a workspace',
              filterable: true,
              entries: <AleraDropdownFieldEntry<String?>>[
                for (final workspace in workspaces)
                  AleraDropdownFieldEntry(
                    value: workspace.id,
                    label: workspace.name,
                  ),
              ],
              onChanged: form.setWorkspace,
            ),
            if (source?.value case final snapshot?
                when snapshot.hasUncommittedChanges)
              const Padding(
                padding: EdgeInsets.only(top: AleraTokens.space8),
                child: AleraNotice(
                  icon: AleraIcons.warning,
                  message: 'This workspace has uncommitted changes. Isolated runs start from its last commit.',
                ),
              ),
            if (source?.error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: AleraTokens.space8),
                child: AleraNotice(
                  icon: AleraIcons.warning,
                  message: runErrorMessage(error),
                ),
              ),
            const AleraSectionHeader(label: 'Isolation'),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<RunIsolation>(
                segments: const <ButtonSegment<RunIsolation>>[
                  ButtonSegment(
                    value: RunIsolation.isolated,
                    label: Text('Isolated'),
                  ),
                  ButtonSegment(
                    value: RunIsolation.shared,
                    label: Text('Shared'),
                  ),
                ],
                selected: <RunIsolation>{draft.isolation},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    form.setIsolation(selection.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space4),
              child: Text(
                isolated
                    ? 'Each task gets its own worktree; results integrate one at a time.'
                    : 'Workers share this workspace. Nothing is integrated or cleaned up.',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.foregroundMuted),
              ),
            ),
            if (isolated) ...<Widget>[
              const AleraSectionHeader(label: 'Template'),
              AleraDropdownField<String>(
                value: selectedRecipe.key,
                entries: recipeEntries,
                onChanged: (key) => form.setRecipe(
                  recipes
                      .where((recipe) => recipe.source.key == key)
                      .firstOrNull
                      ?.source,
                ),
              ),
              if (catalog?.value?.projectError case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: AleraTokens.space4),
                  child: Text(error),
                ),
            ],
            const AleraSectionHeader(label: 'Profiles'),
            AleraDropdownField<String?>(
              labelText: 'Coordinator',
              value: draft.coordinatorProfileId,
              hintText: 'Choose a profile',
              entries: profileEntries,
              onChanged: form.setCoordinator,
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraDropdownField<String?>(
              labelText: 'Worker',
              value: draft.workerProfileId,
              hintText: 'Same as the coordinator',
              entries: profileEntries,
              onChanged: form.setWorker,
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraDropdownField<int>(
              labelText: 'Concurrent Workers',
              value: draft.maxConcurrent,
              entries: <AleraDropdownFieldEntry<int>>[
                for (final count in newRunConcurrencyChoices)
                  AleraDropdownFieldEntry(value: count, label: '$count'),
              ],
              onChanged: form.setMaxConcurrent,
            ),
            const SizedBox(height: AleraTokens.space8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: draft.approvalRequired,
              onChanged: form.setApprovalRequired,
              title: const Text('Require Plan Approval'),
              subtitle: const Text(
                'Workers wait until you approve the coordinator\'s plan.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, MobileNewRunForm form) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final result = await form.submit();
      if (result == null || !context.mounted) return;
      if (result.coordinatorError case final error?) {
        messenger.showSnackBar(SnackBar(content: Text(error)));
      }
      unawaited(
        navigator.pushReplacement<void, void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                RunDetailScreen(hostId: hostId, runId: result.runId),
          ),
        ),
      );
    } on Object catch (error, stackTrace) {
      showActionFailure(
        messenger,
        action: 'start the run',
        error: error,
        stackTrace: stackTrace,
        message: runErrorMessage(error),
      );
    }
  }
}
