part of 'workflow_catalog_pane.dart';

extension _WorkflowCatalogActions on _WorkflowCatalogPaneState {
  void _beginEdit({required bool copy}) {
    _change(() {
      _editing = true;
      _editRevision = copy ? null : _selected!['catalogRevision'] as int?;
      _notice = copy
          ? 'Choose a unique recipe id before saving if a Personal recipe already uses this id.'
          : 'This edit changes the catalog only. Active runs keep their approved definitions.';
    });
    _retainDraft();
  }

  Future<void> _validate() => _run(() async {
    await _repository.validate(_document.text);
    if (mounted) {
      _change(() => _notice = 'Recipe and role contracts are valid.');
    }
  });

  Future<void> _save() => _run(() async {
    final repository = _repository;
    final drafts = ref.read(workflowCatalogDraftProvider.notifier);
    final submitted = ref.read(workflowCatalogDraftProvider);
    final text = _document.text;
    final revision = _editRevision;
    final sourceId = _object(_selected!['source'])['id'];
    if (revision != null) {
      final validated = await repository.validate(text);
      if (_object(validated['recipe'])['id'] != sourceId) {
        throw StateError(
          'Keep the recipe id when editing. Use Copy To Personal for a new id.',
        );
      }
    }
    final record = await repository.save(text, revision);
    drafts.clearIfCurrent(submitted);
    if (!mounted) return;
    final document = await repository.document(record['recipe']);
    if (!mounted) return;
    _change(() {
      _selected = record;
      _editing = false;
      _document.text = document;
      _notice = 'Personal recipe saved.';
    });
    final catalog = await _repository.list(_workspaceId);
    if (mounted) {
      _change(
        () => _entries = (catalog['entries']! as List).map(_object).toList(),
      );
    }
  });

  Future<void> _cancel() => _run(() async {
    final document = await _repository.document(_selected!['recipe']);
    if (mounted) {
      _change(() {
        _document.text = document;
        _editing = false;
        _exporting = false;
        _preview = null;
      });
      ref.read(workflowCatalogDraftProvider.notifier).retain(null);
    }
  });

  Future<void> _exportPreview() => _run(() async {
    final preview = await _repository.export(
      workspaceId: _workspaceId!,
      filename: _filename.text,
      document: _document.text,
    );
    if (mounted) _change(() => _preview = preview);
  });

  Future<void> _exportApply() => _run(() async {
    final preview = _preview!;
    final result = await _repository.export(
      workspaceId: preview['workspaceId']! as String,
      filename: _filename.text,
      document: preview['after']! as String,
      expectedDigest: preview['expectedDigest']! as String,
    );
    if (!mounted) return;
    _change(() {
      _exporting = false;
      _preview = null;
      _notice =
          'Recipe exported to ${preview['path']}.'
          '${result['retainedPath'] == null ? '' : ' Previous content retained at ${result['retainedPath']}.'}';
    });
    final catalog = await _repository.list(_workspaceId);
    if (mounted) {
      _change(
        () => _entries = (catalog['entries']! as List).map(_object).toList(),
      );
    }
  });

  Future<void> _open() => _run(() async {
    final source = _object(_selected!['source']);
    final state = ref.read(workbenchControllerProvider);
    final workspace = state.workspacesByProject.values
        .expand((items) => items)
        .where(
          (w) =>
              w.id == source['workspaceId'] &&
              w.isActive &&
              w.hostId == 'local',
        )
        .firstOrNull;
    if (workspace == null) throw StateError('Workspace is unavailable.');
    final project = state.projects
        .where((p) => p.id == workspace.projectId)
        .firstOrNull;
    if (project == null) throw StateError('Project is unavailable.');
    final controller = ref.read(workbenchControllerProvider.notifier);
    await controller.selectWorkspace(project: project, workspace: workspace);
    await controller.openEditorTab(
      workspace: workspace,
      relativePath: source['path']! as String,
    );
    if (mounted) {
      _change(
        () => _notice =
            'File opened in its workspace. Close Settings to view it.',
      );
    }
  });
}
