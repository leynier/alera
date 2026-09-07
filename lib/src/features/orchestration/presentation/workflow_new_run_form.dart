import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/orchestration/infra/workflow_catalog_repository.dart';
import 'package:alera/src/features/orchestration/infra/workflow_lifecycle_repository.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class WorkflowNewRunForm extends StatefulWidget {
  const WorkflowNewRunForm({
    super.key,
    required this.repository,
    required this.catalog,
    required this.workspaces,
    required this.profiles,
    required this.onCreated,
    required this.onBack,
  });
  final WorkflowLifecycleRepository repository;
  final WorkflowCatalogRepository catalog;
  final List<({String id, String label})> workspaces;
  final List<AgentProfile> profiles;
  final ValueChanged<String> onCreated;
  final VoidCallback onBack;

  @override
  State<WorkflowNewRunForm> createState() => _WorkflowNewRunFormState();
}

class _WorkflowNewRunFormState extends State<WorkflowNewRunForm> {
  final _objective = TextEditingController();
  final _requestId = const Uuid().v4();
  final _roleProfiles = <String, String>{};
  String? _workspaceId;
  String? _recipeKey;
  String? _coordinator;
  Map<String, Object?>? _source;
  Map<String, Object?>? _recipe;
  List<Map<String, Object?>> _entries = [];
  String? _pendingDocument;
  Object? _error;
  String? _catalogError;
  int _concurrency = 4;
  bool _busy = false;
  int _generation = 0;

  @override
  void dispose() {
    _objective.dispose();
    super.dispose();
  }

  Future<void> _selectWorkspace(String id) async {
    final generation = ++_generation;
    setState(() {
      _workspaceId = id;
      _source = null;
      _recipe = null;
      _entries = [];
      _recipeKey = null;
      _roleProfiles.clear();
      _error = null;
      _catalogError = null;
      _busy = true;
    });
    try {
      final source = await widget.repository.source(id);
      final catalog = await widget.catalog.list(id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _source = source;
        _entries = (catalog['entries']! as List)
            .map((entry) => Map<String, Object?>.from(entry as Map))
            .toList();
        _catalogError = catalog['projectError'] as String?;
      });
    } on Object catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _selectRecipe(String key) async {
    final generation = ++_generation;
    final entry = _entries.firstWhere(
      (entry) => _key(entry['source']! as Map) == key,
    );
    setState(() {
      _busy = true;
      _recipe = null;
      _recipeKey = key;
      _roleProfiles.clear();
      _error = null;
    });
    try {
      final recipe = await widget.catalog.read(
        Map<String, Object?>.from(entry['source']! as Map),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _recipe = recipe;
        for (final role in (recipe['recipe']! as Map)['roles']! as List) {
          if (_coordinator != null) {
            _roleProfiles[(role as Map)['id']! as String] = _coordinator!;
          }
        }
      });
    } on Object catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _propose() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _pendingDocument ??= await widget.repository.proposalDocument(
        requestId: _requestId,
        source: _source!,
        recipe: _recipe!,
        objective: _objective.text,
        coordinatorProfileId: _coordinator!,
        roleProfiles: _roleProfiles,
        maxConcurrent: _concurrency,
      );
      final draft = await widget.repository.createProposal(_pendingDocument!);
      final id = draft['id']! as String;
      if (mounted) widget.onCreated(id);
      // Creation may navigate to the durable proposal surface. The explicit
      // Propose Plan action still owns its one-shot coordinator launch.
      await widget.repository.startCoordinator(id);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _busy || _pendingDocument != null;
    final roles = _recipe == null
        ? const <Map>[]
        : ((_recipe!['recipe']! as Map)['roles']! as List).cast<Map>();
    final validProfiles = widget.profiles.map((profile) => profile.id).toSet();
    final ready =
        _source != null &&
        _recipe != null &&
        _objective.text.trim().isNotEmpty &&
        validProfiles.contains(_coordinator) &&
        roles.every(
          (role) => validProfiles.contains(_roleProfiles[role['id']]),
        );
    final profileEntries = [
      for (final profile in widget.profiles)
        AleraDropdownFieldEntry(
          value: profile.id,
          label: '${profile.name} (${profile.agentType})',
        ),
    ];
    return ListView(
      padding: const EdgeInsets.all(AleraTokens.space16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : widget.onBack,
            child: const Text('Back To Runs'),
          ),
        ),
        Text('New Workflow Run', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AleraTokens.space8),
        const Text(
          'Choose a source and recipe. The coordinator proposes a plan; you review it before any worker starts.',
        ),
        const SizedBox(height: AleraTokens.space16),
        AleraDropdownField<String>(
          value: _workspaceId,
          labelText: 'Project / Workspace',
          hintText: 'Select a local Git workspace',
          filterable: true,
          enabled: !locked,
          entries: [
            for (final workspace in widget.workspaces)
              AleraDropdownFieldEntry(
                value: workspace.id,
                label: workspace.label,
              ),
          ],
          onChanged: _selectWorkspace,
        ),
        if (widget.workspaces.isEmpty)
          const Text(
            'Add a local Git project and workspace before creating a workflow.',
          ),
        if (_source != null) ...[
          const SizedBox(height: AleraTokens.space12),
          Text('Source Commit', style: Theme.of(context).textTheme.labelMedium),
          SelectableText(
            _source!['sha']! as String,
            style: AleraTokens.monoCompactStyle,
          ),
          Text(
            _source!['hasUncommittedChanges'] == true
                ? 'This workspace has uncommitted changes. They remain intact and are excluded from the workflow source.'
                : 'The workflow starts from this exact commit. Later uncommitted changes are excluded.',
          ),
          const SizedBox(height: AleraTokens.space16),
          AleraDropdownField<String>(
            value: _recipeKey,
            labelText: 'Recipe',
            hintText: 'Select a recipe',
            filterable: true,
            enabled: !locked,
            entries: [
              for (final entry in _entries)
                AleraDropdownFieldEntry(
                  value: _key(entry['source']! as Map),
                  label:
                      '${entry['name'] ?? 'Invalid Recipe'} (${_origin(entry['source']! as Map)})',
                  enabled: entry['error'] == null,
                ),
            ],
            onChanged: _selectRecipe,
          ),
          if (_catalogError != null)
            Text('Project recipes are unavailable: $_catalogError'),
        ],
        if (_recipe != null) ...[
          const SizedBox(height: AleraTokens.space12),
          Text((_recipe!['recipe']! as Map)['description']! as String),
          const SizedBox(height: AleraTokens.space16),
          AleraTextField(
            controller: _objective,
            labelText: 'Objective',
            minLines: 3,
            maxLines: 8,
            enabled: !locked,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AleraTokens.space16),
          AleraDropdownField<String>(
            value: _coordinator,
            labelText: 'Coordinator Profile',
            hintText: 'Select an Agent Profile',
            entries: profileEntries,
            filterable: true,
            enabled: !locked,
            onChanged: (id) => setState(() {
              _coordinator = id;
              for (final role in roles) {
                _roleProfiles.putIfAbsent(role['id']! as String, () => id);
              }
            }),
          ),
          if (widget.profiles.isEmpty)
            const Text(
              'Create an Agent Profile in Settings before proposing a plan.',
            ),
          const SizedBox(height: AleraTokens.space12),
          const Text(
            'Role profiles initially use the coordinator selection. Review each binding; no provider or model is imposed by the recipe.',
          ),
          for (final role in roles) ...[
            const SizedBox(height: AleraTokens.space12),
            AleraDropdownField<String>(
              value: _roleProfiles[role['id']],
              labelText: '${role['name']} Profile',
              hintText: 'Select an Agent Profile',
              entries: profileEntries,
              enabled: !locked,
              filterable: true,
              onChanged: (id) =>
                  setState(() => _roleProfiles[role['id']! as String] = id),
            ),
          ],
          const SizedBox(height: AleraTokens.space16),
          AleraDropdownField<int>(
            value: _concurrency,
            labelText: 'Concurrent Workers',
            enabled: !locked,
            entries: [
              for (var count = 1; count <= 16; count++)
                AleraDropdownFieldEntry(value: count, label: '$count'),
            ],
            onChanged: (value) => setState(() => _concurrency = value),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AleraTokens.space12),
          SelectableText(_error.toString()),
          if (_pendingDocument == null && _workspaceId != null)
            TextButton(
              onPressed: _busy ? null : () => _selectWorkspace(_workspaceId!),
              child: const Text('Refresh Source And Recipes'),
            ),
        ],
        if (_pendingDocument != null)
          const Text(
            'The selection is retained for an identical retry. Return to the runs to start a different proposal.',
          ),
        const SizedBox(height: AleraTokens.space16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: !_busy && (ready || _pendingDocument != null)
                ? _propose
                : null,
            child: Text(
              _busy
                  ? 'Preparing Proposal'
                  : _pendingDocument != null
                  ? 'Retry Proposal'
                  : 'Propose Plan',
            ),
          ),
        ),
      ],
    );
  }
}

String _key(Map source) =>
    '${source['origin']}:${source['workspaceId'] ?? ''}:${source['path'] ?? source['id']}';
String _origin(Map source) => switch (source['origin']) {
  'builtIn' => 'Built-in',
  'personal' => 'Personal',
  'project' => 'Project: ${source['path']}',
  _ => 'Unknown Origin',
};
