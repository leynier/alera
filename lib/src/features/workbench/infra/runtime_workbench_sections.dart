part of 'runtime_workbench_repository.dart';

mixin _RuntimeWorkbenchSections implements WorkspaceSectionRepository {
  RuntimeHostClient get _client;
  RuntimeChangeCoalescer get _coalescer;
  Future<void> _ensureReady();

  @override
  Future<bool> supportsSections() async {
    await _ensureReady();
    final client = _client;
    return client is RuntimeHostCapabilityClient &&
        await (client as RuntimeHostCapabilityClient).supportsRuntimeCapability(
          aleraRuntimeHostWorkspaceSectionsCapability,
        );
  }

  @override
  Stream<WorkspaceSectionSnapshot> watchSections() => runtimeSnapshotStream(
    client: _client,
    eventNames: const {
      'workspaceSectionsChanged',
      'workspacesChanged',
      'projectsChanged',
    },
    readSnapshot: () async {
      final supported = await supportsSections();
      return WorkspaceSectionSnapshot(
        supported: supported,
        sections: supported ? await listSections() : const [],
      );
    },
    coalesceKey: 'workspace-sections',
    coalescer: _coalescer,
  );

  @override
  Future<List<WorkspaceSection>> listSections() async {
    await _ensureReady();
    return _asList(await _client.runtimeRequest('workspaceSection.list'))
        .map(WorkspaceSection.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> createSection(String name, String workspaceId) async {
    await _ensureReady();
    await _client.runtimeRequest('workspaceSection.create', {
      'name': name,
      'workspaceId': workspaceId,
    });
  }

  @override
  Future<void> setSection(String workspaceId, String? sectionId) async {
    await _ensureReady();
    await _client.runtimeRequest('workspaceSection.setForWorkspace', {
      'workspaceId': workspaceId,
      'sectionId': sectionId,
    });
  }

  @override
  Future<void> removeSection(String sectionId) async {
    await _ensureReady();
    await _client.runtimeRequest('workspaceSection.remove', {'id': sectionId});
  }
}
