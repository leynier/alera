import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/activity/application/activity_navigation.dart';
import 'package:alera/src/features/activity/domain/activity_section.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/runs/application/run_actions.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/domain/recipe_catalog_entry.dart';
import 'package:alera/src/features/runs/domain/run_create_request.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/presentation/new_run_form.dart';
import 'package:alera/src/features/runs/presentation/run_remote_workspaces_notice.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showNewRunDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const NewRunDialog());

/// Creates a run. A proposal is just a run in Planning, so Create closes the
/// dialog and selects the new run, whose Overview shows the coordinator
/// preparing its plan.
class NewRunDialog extends ConsumerStatefulWidget {
  const NewRunDialog({super.key});

  @override
  ConsumerState<NewRunDialog> createState() => _NewRunDialogState();
}

class _NewRunDialogState extends ConsumerState<NewRunDialog> {
  final TextEditingController _objective = TextEditingController();
  final Map<String, String> _roleProfiles = <String, String>{};
  RunIsolation _isolation = RunIsolation.isolated;
  String? _workspaceId;
  RunSource? _source;
  Object? _sourceError;
  List<RecipeCatalogEntry> _recipes = const <RecipeCatalogEntry>[];
  String? _catalogError;
  String? _recipeKey;
  List<RecipeRole> _roles = const <RecipeRole>[];
  String? _coordinator;
  String? _worker;
  int _concurrency = 4;
  bool _approval = false;
  bool _loading = false;
  int _generation = 0;
  late String _requestId = RunActions.newRequestId();

  @override
  void dispose() {
    _objective.dispose();
    super.dispose();
  }

  /// A changed form is a different request, never a replay of a failed one.
  void _edit(VoidCallback change) => setState(() {
    change();
    _requestId = RunActions.newRequestId();
    ref.read(runActionsProvider.notifier).clearError(RunActions.createKey);
  });

  Future<void> _load() async {
    final workspaceId = _workspaceId;
    if (workspaceId == null || _isolation == RunIsolation.shared) return;
    final generation = ++_generation;
    setState(() => _loading = true);
    final repository = ref.read(runRepositoryProvider);
    final recipes = ref.read(recipeRepositoryProvider);
    try {
      final results = await Future.wait<Object?>(<Future<Object?>>[
        repository
            .source(workspaceId)
            .then<Object?>((v) => v, onError: (Object e) => e),
        recipes
            .list(workspaceId)
            .then<Object?>((v) => v, onError: (Object e) => e),
      ]);
      if (!mounted || generation != _generation) return;
      final source = results[0];
      final catalog = results[1];
      setState(() {
        _source = source is RunSource ? source : null;
        _sourceError = source is RunSource ? null : source;
        if (catalog is Map<String, Object?>) {
          _recipes = <RecipeCatalogEntry>[
            for (final entry
                in catalog['entries'] as List? ?? const <Object?>[])
              if (entry is Map) RecipeCatalogEntry.fromJson(entry),
          ];
          _catalogError = catalog['projectError'] as String?;
        } else {
          _recipes = const <RecipeCatalogEntry>[];
          _catalogError = catalog == null ? null : runErrorMessage(catalog);
        }
        final current = _recipes.where((entry) => entry.key == _recipeKey);
        if (current.isEmpty) {
          _recipeKey = _recipes
              .where((entry) => entry.isFreeform && entry.usable)
              .firstOrNull
              ?.key;
        }
      });
      await _loadRoles();
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadRoles() async {
    final entry = _recipes.where((item) => item.key == _recipeKey).firstOrNull;
    final generation = _generation;
    if (entry == null) {
      setState(() => _roles = const <RecipeRole>[]);
      return;
    }
    try {
      final record = await ref
          .read(recipeRepositoryProvider)
          .read(entry.source);
      if (!mounted || generation != _generation) return;
      setState(() {
        _roles = RecipeRole.fromRecord(record);
        _roleProfiles.removeWhere(
          (role, _) => !_roles.any((item) => item.id == role),
        );
        final fallback = _coordinator;
        if (fallback != null) {
          for (final role in _roles) {
            _roleProfiles.putIfAbsent(role.id, () => fallback);
          }
        }
      });
    } on Object catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _catalogError = runErrorMessage(error));
      }
    }
  }

  bool _ready(Set<String> profiles) {
    if (_objective.text.trim().isEmpty || _workspaceId == null) return false;
    if (!profiles.contains(_coordinator)) return false;
    if (_isolation == RunIsolation.shared) {
      return _worker == null || profiles.contains(_worker);
    }
    return _source != null &&
        _recipeKey != null &&
        _roles.every((role) => profiles.contains(_roleProfiles[role.id]));
  }

  Future<void> _create() async {
    final recipe = _recipes.where((item) => item.key == _recipeKey).firstOrNull;
    final isolated = _isolation == RunIsolation.isolated;
    final result = await ref
        .read(runActionsProvider.notifier)
        .create(
          RunCreateRequest(
            requestId: _requestId,
            workspaceId: _workspaceId!,
            objective: _objective.text.trim(),
            isolation: _isolation,
            recipeSource: isolated ? recipe?.source : null,
            coordinatorProfileId: _coordinator!,
            roleProfiles: isolated
                ? Map<String, String>.of(_roleProfiles)
                : const <String, String>{},
            workerProfileId: isolated ? null : _worker,
            maxConcurrent: _concurrency,
            approvalRequired: _approval,
          ),
        );
    if (result == null || !mounted) return;
    ref.read(activityNavigationProvider.notifier)
      ..open(ActivitySection.runs)
      ..selectRun(result.run.runId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final workbench = ref.watch(workbenchControllerProvider);
    final profiles = ref.watch(agentProfilesProvider);
    final profileEntries = newRunProfileEntries(profiles.value ?? const []);
    final profileIds = <String>{
      for (final entry in profileEntries) entry.value,
    };
    final actions = ref.watch(runActionsProvider);
    final busy = actions.busyFor(RunActions.createKey) != null;
    final error = actions.errorFor(RunActions.createKey);
    final isolated = _isolation == RunIsolation.isolated;
    final workspaces = newRunWorkspaceEntries(workbench, _isolation);
    final muted = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final source = _source;
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          AleraDialogHeader(
            title: 'New Run',
            onClose: () => Navigator.of(context).pop(),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AleraTokens.space16),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                spacing: AleraTokens.space12,
                children: <Widget>[
                  AleraTextField(
                    key: const ValueKey<String>('newRunObjective'),
                    controller: _objective,
                    labelText: 'Objective',
                    hintText: 'What should this run deliver?',
                    minLines: 2,
                    maxLines: 8,
                    autofocus: true,
                    enabled: !busy,
                    onChanged: (_) => _edit(() {}),
                  ),
                  AleraDropdownField<String>(
                    key: const ValueKey<String>('newRunWorkspace'),
                    labelText: 'Workspace',
                    hintText: 'Choose a workspace',
                    value: workspaces.any((e) => e.value == _workspaceId)
                        ? _workspaceId
                        : null,
                    entries: workspaces,
                    enabled: !busy,
                    filterable: workspaces.length > 6,
                    filterHintText: 'Search Workspaces',
                    onChanged: (id) {
                      _edit(() {
                        _workspaceId = id;
                        _source = null;
                        _sourceError = null;
                      });
                      unawaited(_load());
                    },
                  ),
                  if (newRunHidesRemoteWorkspaces(workbench))
                    const RunRemoteWorkspacesNotice(),
                  if (workspaces.isEmpty)
                    Text(
                      isolated
                          ? 'Add a local Git project and workspace to create an isolated run.'
                          : 'Add a local workspace to create a run.',
                      style: muted,
                    ),
                  if (isolated && source != null)
                    Text(
                      'Source commit ${source.shortSha}.${source.hasUncommittedChanges ? ' Uncommitted changes stay in place.' : ''}',
                      key: const ValueKey<String>('newRunSource'),
                      style: muted,
                    ),
                  if (isolated && _sourceError != null)
                    AleraInlineNotice(
                      tone: .warning,
                      message: runErrorMessage(_sourceError!),
                    ),
                  newRunIsolationChoice(
                    selected: _isolation,
                    enabled: !busy,
                    onChanged: (value) {
                      _edit(() => _isolation = value);
                      unawaited(_load());
                    },
                  ),
                  if (isolated)
                    NewRunTemplateFields(
                      entries: _recipes,
                      selectedKey: _recipeKey,
                      enabled: !busy && !_loading,
                      catalogError: _catalogError,
                      onSelected: (key) {
                        _edit(() => _recipeKey = key);
                        unawaited(_loadRoles());
                      },
                      onManage: () => unawaited(
                        openSettingsDialog(
                          context,
                          initialSectionId: 'recipes',
                        ),
                      ),
                      roles: _roles,
                      roleProfiles: _roleProfiles,
                      onRoleProfile: (value) =>
                          _edit(() => _roleProfiles[value.$1] = value.$2),
                      profiles: profileEntries,
                    ),
                  AleraDropdownField<String>(
                    key: const ValueKey<String>('newRunCoordinator'),
                    labelText: 'Coordinator',
                    hintText: 'Choose an Agent Profile',
                    value: _coordinator,
                    entries: profileEntries,
                    enabled: !busy,
                    filterable: profileEntries.length > 6,
                    filterHintText: 'Search Profiles',
                    onChanged: (id) => _edit(() {
                      _coordinator = id;
                      for (final role in _roles) {
                        _roleProfiles.putIfAbsent(role.id, () => id);
                      }
                    }),
                  ),
                  if (profiles.hasValue && profileEntries.isEmpty)
                    Text(
                      'Create an Agent Profile in Settings before creating a run.',
                      style: muted,
                    ),
                  if (!isolated)
                    AleraDropdownField<String>(
                      key: const ValueKey<String>('newRunWorker'),
                      labelText: 'Worker Profile',
                      hintText: 'Same as the coordinator',
                      value: _worker,
                      entries: profileEntries,
                      enabled: !busy,
                      onChanged: (id) => _edit(() => _worker = id),
                    ),
                  AleraDropdownField<int>(
                    key: const ValueKey<String>('newRunConcurrency'),
                    labelText: 'Concurrent Workers',
                    value: _concurrency,
                    enabled: !busy,
                    entries: <AleraDropdownFieldEntry<int>>[
                      for (var count = 1; count <= 16; count++)
                        AleraDropdownFieldEntry<int>(
                          value: count,
                          label: '$count',
                        ),
                    ],
                    onChanged: (value) => _edit(() => _concurrency = value),
                  ),
                  AleraCheckbox(
                    key: const ValueKey<String>('newRunApproval'),
                    label: 'Require Plan Approval',
                    value: _approval,
                    enabled: !busy,
                    onChanged: (value) => _edit(() => _approval = value),
                  ),
                  Text(
                    'The coordinator proposes a plan and waits for your approval before any worker starts. Stage gates defined by the template always need your approval.',
                    style: muted,
                  ),
                  if (error != null)
                    AleraInlineNotice(
                      tone: .error,
                      message: runErrorMessage(error),
                    ),
                  Row(
                    mainAxisAlignment: .end,
                    spacing: AleraTokens.space8,
                    children: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        key: const ValueKey<String>('newRunCreate'),
                        onPressed: !busy && _ready(profileIds)
                            ? () => unawaited(_create())
                            : null,
                        child: Text(busy ? 'Creating…' : 'Create Run'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
