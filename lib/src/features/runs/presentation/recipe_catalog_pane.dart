import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_master_detail.dart';
import 'package:alera/src/features/runs/application/recipe_catalog_draft.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:alera/src/features/runs/domain/run_error_messages.dart';
import 'package:alera/src/features/runs/infra/recipe_repository.dart';
import 'package:alera/src/features/keyboard/domain/key_chord.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'recipe_detail.dart';
import 'run_remote_workspaces_notice.dart';

part 'recipe_catalog_actions.dart';
part 'recipe_catalog_recovery.dart';

final Logger _logger = Logger('RecipeCatalogPane');

class RecipeCatalogPane extends ConsumerStatefulWidget {
  const RecipeCatalogPane({super.key});
  @override
  ConsumerState<RecipeCatalogPane> createState() => _RecipeCatalogPaneState();
}

class _RecipeCatalogPaneState extends ConsumerState<RecipeCatalogPane> {
  final _document = TextEditingController();
  final _filename = TextEditingController();
  final _searchController = TextEditingController();
  List<Map<String, Object?>> _entries = [];
  Map<String, Object?>? _selected;
  Map<String, Object?>? _preview;
  Map<String, Object?>? _recovery;
  RecipeCatalogEdit? _recoveryDraft;
  String? _workspaceId;
  String? _error;
  String? _projectError;
  String? _notice;
  String _search = '';
  bool _busy = true;
  bool _editing = false;
  bool _exporting = false;
  int? _editRevision;
  Object _editSession = Object();
  StreamSubscription<void>? _catalogChanges;
  RuntimeChangeCoalescer? _coalescer;

  RecipeRepository get _repository => ref.read(recipeRepositoryProvider);
  bool get _locked => _busy || _editing || _exporting;

  void _change(VoidCallback update) => setState(update);

  @override
  void initState() {
    super.initState();
    final draft = ref.read(recipeCatalogDraftProvider);
    if (draft != null) {
      _selected = draft.record;
      _document.text = draft.document;
      _editRevision = draft.revision;
      _editSession = draft.session;
      _workspaceId = draft.workspaceId;
      _editing = true;
    }
    _document.addListener(_retainDraft);
    Future.microtask(_reload);
    final coalescer = ref.read(runtimeChangeCoalescerProvider);
    _coalescer = coalescer;
    _catalogChanges = _repository.catalogChanges().listen(
      (_) => coalescer.schedule(_catalogKey, this, _refreshEntries),
      onError: (Object _) {},
    );
  }

  static const String _catalogKey = 'recipes:catalog';

  /// A host change refreshes only the list: it must not clear a notice, an
  /// error or the busy state of an edit in progress.
  Future<void> _refreshEntries() async {
    if (!mounted) return;
    try {
      final catalog = await _repository.list(_workspaceId);
      if (!mounted) return;
      setState(() {
        _entries = (catalog['entries']! as List).map(_object).toList();
        _projectError = catalog['projectError'] as String?;
      });
    } on Object {
      // The next change or an explicit reload reports the failure.
    }
  }

  void _retainDraft() {
    if (!_editing || _selected == null) return;
    ref
        .read(recipeCatalogDraftProvider.notifier)
        .retain(
          RecipeCatalogEdit(
            _selected!,
            _document.text,
            _editRevision,
            _workspaceId,
            _editSession,
          ),
        );
  }

  @override
  void dispose() {
    _coalescer?.cancel(_catalogKey, this);
    unawaited(_catalogChanges?.cancel());
    _document.dispose();
    _filename.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on Object catch (error, stackTrace) {
      _logger.warning('Recipe action failed', error, stackTrace);
      if (mounted) setState(() => _error = runErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() => _run(() async {
    final catalog = await _repository.list(_workspaceId);
    if (!mounted) return;
    setState(() {
      _entries = (catalog['entries']! as List).map(_object).toList();
      _projectError = catalog['projectError'] as String?;
    });
  });

  Future<void> _select(Map<String, Object?> entry) => _run(() async {
    final source = _object(entry['source']);
    if (entry['error'] != null) {
      setState(() {
        _selected = entry;
        _document.clear();
      });
      return;
    }
    final record = await _repository.read(source);
    final document = await _repository.document(record['recipe']);
    if (!mounted) return;
    setState(() {
      _selected = record;
      _document.text = document;
    });
  });

  @override
  Widget build(BuildContext context) {
    ref.listen(recipeCatalogDraftProvider, (previous, next) {
      if (!_editing || next == null || !identical(next.session, _editSession)) {
        return;
      }
      if (!identical(next.record, _selected) ||
          next.revision != _editRevision) {
        setState(() {
          _selected = next.record;
          _editRevision = next.revision;
          _recovery = null;
          _recoveryDraft = null;
        });
      }
    });
    final state = ref.watch(workbenchControllerProvider);
    final candidates = state.workspacesByProject.values
        .expand((items) => items)
        .where(
          (w) =>
              w.isActive &&
              state.projects.any(
                (p) => p.id == w.projectId && p.isGitRepository,
              ),
        )
        .toList();
    final workspaces = candidates
        .where((w) => !isRemoteWorkspaceHostId(w.hostId))
        .toList();
    final workspaceExists = workspaces.any((w) => w.id == _workspaceId);
    final selected = _selected;
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AleraSearchField(
          controller: _searchController,
          hintText: 'Search Recipes',
          onChanged: (value) => setState(() => _search = value.toLowerCase()),
        ),
        const SizedBox(height: AleraTokens.space8),
        Expanded(child: _recipeList()),
      ],
    );
    final detail = selected == null
        ? const AleraEmptyState(
            title: 'Choose A Recipe',
            message: 'Inspect its stages and role contracts, then copy it to Personal to make it your own.',
          )
        : RecipeDetail(
            record: selected,
            document: _document,
            filename: _filename,
            editing: _editing,
            exporting: _exporting,
            busy: _busy,
            preview: _preview,
            onEdit: () => _beginEdit(copy: false),
            onCopy: () => _beginEdit(copy: true),
            onValidate: _validate,
            onSave: _save,
            onCancel: _cancel,
            onExport: workspaceExists
                ? () => setState(() {
                    _exporting = true;
                    _filename.text =
                        '${_object(selected['recipe'])['id']}.yaml';
                  })
                : null,
            onPreview: workspaceExists ? _exportPreview : null,
            onApply: workspaceExists ? _exportApply : null,
            onFilenameChanged: (_) => setState(() => _preview = null),
            onOpen: _object(selected['source'])['origin'] == 'project'
                ? _open
                : null,
            recovery: _recovery,
            onReviewCurrent: _reviewCurrent,
            onKeepDraft: () => _useReviewedRecipe(useCurrent: false),
            onUseCurrent: () => _useReviewedRecipe(useCurrent: true),
            onCancelReview: () => setState(() {
              _recovery = null;
              _recoveryDraft = null;
            }),
          );
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(workspaceExists ? _workspaceId : ''),
                  initialValue: workspaceExists ? _workspaceId : '',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Project Workspace',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Built-in And Personal'),
                    ),
                    for (final workspace in workspaces)
                      DropdownMenuItem(
                        value: workspace.id,
                        child: Text(
                          '${state.projects.firstWhere((p) => p.id == workspace.projectId).name} / ${workspace.name}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _locked
                      ? null
                      : (value) {
                          setState(() {
                            _workspaceId = value == '' ? null : value;
                            _selected = null;
                          });
                          _reload();
                        },
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              IconButton(
                tooltip: 'Refresh Catalog',
                onPressed: _locked ? null : _reload,
                icon: const Icon(AleraIcons.refresh),
              ),
            ],
          ),
          if (hidesRemoteWorkspaces(candidates)) ...[
            const SizedBox(height: AleraTokens.space8),
            const RunRemoteWorkspacesNotice(),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) _message(_error!, error: true),
          if (_projectError != null) _message(_projectError!, error: true),
          if (_workspaceId != null && !workspaceExists)
            _message(
              'This workspace is unavailable. Select another workspace.',
              error: true,
            ),
          if (_notice != null) _message(_notice!),
          const SizedBox(height: AleraTokens.space16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth <
                    AleraTokens.masterDetailDefaultWidth +
                        AleraTokens.masterDetailMinDetailWidth * 2;
                if (compact) {
                  if (selected == null) return list;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _locked
                              ? null
                              : () => setState(() => _selected = null),
                          icon: const Icon(AleraIcons.back),
                          label: const Text('Recipes'),
                        ),
                      ),
                      Expanded(child: detail),
                    ],
                  );
                }
                return AleraMasterDetail(
                  masterTitle: 'Recipes',
                  master: list,
                  detail: detail,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: error ? AleraTokens.error : AleraTokens.foregroundMuted,
      ),
    ),
  );

  Widget _recipeList() {
    final entries = _entries
        .where(
          (entry) =>
              '${entry['name']} ${entry['description']} ${_origin(entry)}'
                  .toLowerCase()
                  .contains(_search),
        )
        .toList();
    if (entries.isEmpty) {
      return const AleraEmptyState(
        message: 'No recipes match. Try another search or refresh the catalog.',
      );
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final selected =
            _selected != null &&
            _object(_selected!['source']).toString() ==
                _object(entry['source']).toString();
        return AleraActiveRail(
          active: selected,
          child: ListTile(
            enabled: !_locked,
            selected: selected,
            selectedTileColor: AleraActiveRail.selectedColor,
            title: Text(
              entry['name'] as String? ??
                  _object(entry['source'])['path'] as String? ??
                  'Invalid Recipe',
            ),
            subtitle: Text(_origin(entry)),
            trailing: entry['error'] == null
                ? null
                : const Icon(AleraIcons.error),
            onTap: () => _select(entry),
          ),
        );
      },
    );
  }
}

Map<String, Object?> _object(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};

String _origin(Map<String, Object?> record) =>
    switch (_object(record['source'])['origin']) {
      'builtIn' => 'Built-in',
      'personal' => 'Personal',
      'project' => 'Project',
      _ => 'Unknown Origin',
    };
