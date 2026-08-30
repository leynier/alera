import 'package:alera/src/features/workbench/application/workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('RuntimeWorkbenchViewPrefsRepository');

class RuntimeWorkbenchViewPrefsRepository({
  required final RuntimeHostClient client,
  required final WorkbenchViewPrefsRepository legacyRepository,
  final Future<void> Function()? beforeAccess,
}) implements WorkbenchViewPrefsRepository {
  int? _revision;

  @override
  Stream<WorkbenchViewPrefs> get changes => client.runtimeEvents
      .where((event) => event.name == 'workbenchViewPrefsChanged')
      .asyncMap((_) => load());

  @override
  Future<WorkbenchViewPrefs> load() async {
    final local = await legacyRepository.load();
    try {
      await beforeAccess?.call();
      final record = _asMap(
        await client.runtimeRequest('workbenchViewPrefs.get'),
      );
      _revision = (record['revision'] as num?)?.toInt() ?? 0;
      if (record['desktopInitialized'] != true) {
        await _writeShared(local);
        return await _forRuntime(local);
      }
      final merged = _mergeShared(local, _asMap(record['prefs']));
      await legacyRepository.save(merged);
      return await _forRuntime(merged);
    } catch (error, stackTrace) {
      // The local prefs still render, so the only visible symptom is that a
      // change made on another device never arrives.
      _log.warning(
        'could not merge shared view prefs from the runtime; using local only',
        error,
        stackTrace,
      );
      return _forRuntime(local);
    }
  }

  Future<WorkbenchViewPrefs> _forRuntime(WorkbenchViewPrefs prefs) async {
    if (prefs.groupBy != WorkbenchGroupBy.section) return prefs;
    try {
      if (client is RuntimeHostCapabilityClient &&
          await (client as RuntimeHostCapabilityClient)
              .supportsRuntimeCapability(
                aleraRuntimeHostWorkspaceSectionsCapability,
              )) {
        return prefs;
      }
    } catch (error, stack) {
      _log.warning('Could not check section support', error, stack);
    }
    return prefs.copyWith(groupBy: WorkbenchGroupBy.project);
  }

  @override
  Future<void> save(WorkbenchViewPrefs prefs) async {
    await legacyRepository.save(prefs);
    await beforeAccess?.call();
    await _writeShared(prefs);
  }

  Future<void> _writeShared(WorkbenchViewPrefs prefs) async {
    final shared = _sharedJson(prefs);
    if (client is! RuntimeHostCapabilityClient ||
        !await (client as RuntimeHostCapabilityClient)
            .supportsRuntimeCapability(
              aleraRuntimeHostWorkspaceSectionsCapability,
            )) {
      shared.remove('sectionSort');
      shared.remove('collapsedSectionIds');
      shared.remove('othersSectionCollapsed');
      if (prefs.groupBy == WorkbenchGroupBy.section) {
        shared['groupBy'] = 'project';
      }
    }
    final record = _asMap(
      await client.runtimeRequest(
        'workbenchViewPrefs.update',
        <String, Object?>{'expectedRevision': _revision, 'prefs': shared},
      ),
    );
    _revision = (record['revision'] as num?)?.toInt() ?? _revision;
  }
}

Map<String, Object?> _sharedJson(WorkbenchViewPrefs prefs) {
  return <String, Object?>{
    'groupBy': prefs.groupBy.name,
    'sectionSort': prefs.sectionSort.name,
    'collapsedSectionIds': prefs.collapsedSectionIds.toList(),
    'othersSectionCollapsed': prefs.othersSectionCollapsed,
    'projectSort': prefs.projectSort.name,
    'workspaceSort': prefs.workspaceSort.name,
    'selectedProjectIds': prefs.selectedProjectIds.toList(),
    'selectedTagIds': prefs.selectedTagIds.toList(),
    'collapsedProjectIds': prefs.collapsedProjectIds.toList(),
    'collapsedParentWorkspaceIds': prefs.collapsedParentWorkspaceIds.toList(),
    'pinnedSectionCollapsed': prefs.pinnedSectionCollapsed,
    'allSectionCollapsed': prefs.allSectionCollapsed,
    'showPinnedWorkspacesBelow': prefs.showPinnedWorkspacesBelow,
    'workspaceKindFilter': prefs.workspaceKindFilter.name,
    'showActiveWorkspacesOnly': prefs.showActiveWorkspacesOnly,
  };
}

WorkbenchViewPrefs _mergeShared(
  WorkbenchViewPrefs local,
  Map<String, Object?> shared,
) {
  return local.copyWith(
    groupBy: _enumByName(
      WorkbenchGroupBy.values,
      shared['groupBy'],
      local.groupBy,
    ),
    sectionSort: _enumByName(
      WorkbenchSortBy.values,
      shared['sectionSort'],
      local.sectionSort,
    ),
    collapsedSectionIds: shared.containsKey('collapsedSectionIds')
        ? _stringSet(shared['collapsedSectionIds'])
        : local.collapsedSectionIds,
    othersSectionCollapsed:
        shared['othersSectionCollapsed'] as bool? ??
        local.othersSectionCollapsed,
    projectSort: _enumByName(
      WorkbenchSortBy.values,
      shared['projectSort'],
      local.projectSort,
    ),
    workspaceSort: _enumByName(
      WorkbenchSortBy.values,
      shared['workspaceSort'],
      local.workspaceSort,
    ),
    selectedProjectIds: _stringSet(shared['selectedProjectIds']),
    selectedTagIds: _stringSet(shared['selectedTagIds']),
    collapsedProjectIds: _stringSet(shared['collapsedProjectIds']),
    collapsedParentWorkspaceIds: _stringSet(
      shared['collapsedParentWorkspaceIds'],
    ),
    pinnedSectionCollapsed: shared['pinnedSectionCollapsed'] == true,
    allSectionCollapsed: shared['allSectionCollapsed'] == true,
    showPinnedWorkspacesBelow:
        shared['showPinnedWorkspacesBelow'] as bool? ??
        local.showPinnedWorkspacesBelow,
    workspaceKindFilter: _enumByName(
      WorkspaceKindFilter.values,
      shared['workspaceKindFilter'],
      local.workspaceKindFilter,
    ),
    showActiveWorkspacesOnly:
        shared['showActiveWorkspacesOnly'] as bool? ??
        local.showActiveWorkspacesOnly,
  );
}

T _enumByName<T extends Enum>(List<T> values, Object? value, T fallback) {
  if (value is String) {
    for (final item in values) {
      if (item.name == value) return item;
    }
  }
  return fallback;
}

Set<String> _stringSet(Object? value) {
  return <String>{
    if (value is List)
      for (final item in value)
        if (item is String) item,
  };
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return Map<String, Object?>.from(value);
  return const <String, Object?>{};
}
