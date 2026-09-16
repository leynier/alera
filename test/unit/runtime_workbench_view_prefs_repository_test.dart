import 'dart:async';

import 'package:alera/src/features/workbench/application/workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/infra/runtime_workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sections roundtrip on supported hosts and are omitted on older hosts',
    () async {
      final client = _FakeRuntimeHostClient()..supportsSections = true;
      client.responses['workbenchViewPrefs.get'] = {
        'revision': 4,
        'desktopInitialized': true,
        'prefs': {
          'groupBy': 'section',
          'sectionSort': 'recent',
          'collapsedSectionIds': ['s'],
          'othersSectionCollapsed': true,
        },
      };
      final repo = RuntimeWorkbenchViewPrefsRepository(
        client: client,
        legacyRepository: _MemoryViewPrefsRepository(),
      );
      final prefs = await repo.load();
      expect(prefs.groupBy, WorkbenchGroupBy.section);
      expect(prefs.sectionSort, WorkbenchSortBy.recent);
      expect(prefs.collapsedSectionIds, {'s'});
      await repo.save(prefs);
      expect(
        client.payloads['workbenchViewPrefs.update']!.last['prefs'],
        containsPair('groupBy', 'section'),
      );
      expect(
        client.payloads['workbenchViewPrefs.update']!.last['prefs'],
        containsPair('othersSectionCollapsed', true),
      );
      client.supportsSections = false;
      final fallback = await repo.load();
      expect(fallback.groupBy, WorkbenchGroupBy.project);
      expect(fallback.sectionSort, WorkbenchSortBy.recent);
      expect(fallback.collapsedSectionIds, {'s'});
      await repo.save(prefs);
      final old =
          client.payloads['workbenchViewPrefs.update']!.last['prefs'] as Map;
      expect(old['groupBy'], 'project');
      expect(old.containsKey('sectionSort'), isFalse);
      expect(old.containsKey('collapsedSectionIds'), isFalse);
    },
  );

  test('loads and saves the shared active workspace filter', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['workbenchViewPrefs.get'] = <String, Object?>{
        'revision': 4,
        'desktopInitialized': true,
        'prefs': <String, Object?>{'showActiveWorkspacesOnly': true},
      }
      ..responses['workbenchViewPrefs.update'] = <String, Object?>{
        'revision': 5,
      };
    final legacy = _MemoryViewPrefsRepository();
    final repository = RuntimeWorkbenchViewPrefsRepository(
      client: client,
      legacyRepository: legacy,
    );

    final loaded = await repository.load();
    expect(loaded.showActiveWorkspacesOnly, isTrue);

    await repository.save(loaded.copyWith(showActiveWorkspacesOnly: false));
    expect(
      client.payloads['workbenchViewPrefs.update']?.single['prefs'],
      containsPair('showActiveWorkspacesOnly', false),
    );
    expect(legacy.prefs.showActiveWorkspacesOnly, isFalse);
  });

  test('shares the search and source control view options', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['workbenchViewPrefs.get'] = <String, Object?>{
        'revision': 4,
        'desktopInitialized': true,
        'prefs': <String, Object?>{
          'gitDiffViewMode': 'flat',
          'gitDiffGroupMode': 'unified',
          'searchViewAsTree': true,
          'searchIncludeIgnored': true,
        },
      }
      ..responses['workbenchViewPrefs.update'] = <String, Object?>{
        'revision': 5,
      };
    final repository = RuntimeWorkbenchViewPrefsRepository(
      client: client,
      legacyRepository: _MemoryViewPrefsRepository(),
    );

    final loaded = await repository.load();
    expect(loaded.gitDiffViewMode, GitDiffViewMode.flat);
    expect(loaded.gitDiffGroupMode, GitDiffGroupMode.unified);
    expect(loaded.searchViewAsTree, isTrue);
    expect(loaded.searchIncludeIgnored, isTrue);

    await repository.save(loaded.copyWith(searchViewAsTree: false));
    final sent =
        client.payloads['workbenchViewPrefs.update']!.single['prefs'] as Map;
    expect(sent['searchViewAsTree'], isFalse);
    expect(sent['searchIncludeIgnored'], isTrue);
    expect(sent['gitDiffViewMode'], 'flat');
    expect(sent['gitDiffGroupMode'], 'unified');
  });

  test(
    'a paused echo does not restore a locally removed right-sidebar width',
    () async {
      final getStarted = Completer<void>();
      final releaseGet = Completer<void>();
      final client = _FakeRuntimeHostClient()
        ..supportsSections = true
        ..responses['workbenchViewPrefs.get'] = <String, Object?>{
          'revision': 4,
          'desktopInitialized': true,
          'prefs': <String, Object?>{'groupBy': 'project'},
        }
        ..responses['workbenchViewPrefs.update'] = <String, Object?>{
          'revision': 5,
        }
        ..requestGates['workbenchViewPrefs.get'] = (
          started: getStarted,
          release: releaseGet,
        );
      final legacy = _MemoryViewPrefsRepository()
        ..prefs = WorkbenchViewPrefs.defaults.copyWith(
          rightSidebarWidthByWorkspaceId: const <String, double>{'w-1': 360},
        );
      final repository = RuntimeWorkbenchViewPrefsRepository(
        client: client,
        legacyRepository: legacy,
      );

      final echo = repository.load();
      await getStarted.future;
      await repository.save(
        WorkbenchViewPrefs.defaults.copyWith(
          rightSidebarWidthByWorkspaceId: const <String, double>{},
        ),
      );
      expect(legacy.prefs.rightSidebarWidthByWorkspaceId, isEmpty);

      releaseGet.complete();
      final echoed = await echo;
      expect(echoed.rightSidebarWidthByWorkspaceId, isEmpty);
      expect(legacy.prefs.rightSidebarWidthByWorkspaceId, isEmpty);
    },
  );

  test(
    'a failed echo uses the latest local prefs, not the pre-request snapshot',
    () async {
      final getStarted = Completer<void>();
      final releaseGet = Completer<void>();
      final client = _FakeRuntimeHostClient()
        ..supportsSections = true
        ..requestGates['workbenchViewPrefs.get'] = (
          started: getStarted,
          release: releaseGet,
        );
      final legacy = _MemoryViewPrefsRepository()
        ..prefs = WorkbenchViewPrefs.defaults.copyWith(
          rightSidebarWidthByWorkspaceId: const <String, double>{'w-1': 360},
        );
      final repository = RuntimeWorkbenchViewPrefsRepository(
        client: client,
        legacyRepository: legacy,
      );

      final echo = repository.load();
      await getStarted.future;
      await repository.save(
        WorkbenchViewPrefs.defaults.copyWith(
          rightSidebarWidthByWorkspaceId: const <String, double>{},
        ),
      );
      releaseGet.completeError(StateError('runtime unavailable'));
      final echoed = await echo;
      expect(echoed.rightSidebarWidthByWorkspaceId, isEmpty);
      expect(legacy.prefs.rightSidebarWidthByWorkspaceId, isEmpty);
    },
  );

  test(
    'a concurrent local save after merge still wins the load result',
    () async {
      final getStarted = Completer<void>();
      final releaseGet = Completer<void>();
      final client = _FakeRuntimeHostClient()
        ..supportsSections = true
        ..responses['workbenchViewPrefs.get'] = <String, Object?>{
          'revision': 4,
          'desktopInitialized': true,
          'prefs': <String, Object?>{'groupBy': 'project'},
        }
        ..responses['workbenchViewPrefs.update'] = <String, Object?>{
          'revision': 5,
        }
        ..requestGates['workbenchViewPrefs.get'] = (
          started: getStarted,
          release: releaseGet,
        );
      final legacy = _MemoryViewPrefsRepository()
        ..prefs = WorkbenchViewPrefs.defaults.copyWith(
          rightSidebarWidthByWorkspaceId: const <String, double>{'w-1': 360},
        );
      final repository = RuntimeWorkbenchViewPrefsRepository(
        client: client,
        legacyRepository: legacy,
      );

      final echo = repository.load();
      await getStarted.future;
      final sleepSave = repository.save(
        WorkbenchViewPrefs.defaults.copyWith(
          rightSidebarWidthByWorkspaceId: const <String, double>{},
        ),
      );
      releaseGet.complete();
      await echo;
      await sleepSave;
      expect(legacy.prefs.rightSidebarWidthByWorkspaceId, isEmpty);
      expect((await echo).rightSidebarWidthByWorkspaceId, isEmpty);
    },
  );

  test(
    'a queued echo does not overlay an older shared snapshot after a newer save',
    () async {
      final getStarted = Completer<void>();
      final releaseGet = Completer<void>();
      final client = _FakeRuntimeHostClient()
        ..supportsSections = true
        ..responses['workbenchViewPrefs.get'] = <String, Object?>{
          'revision': 4,
          'desktopInitialized': true,
          'prefs': <String, Object?>{'searchViewAsTree': false},
        }
        ..responses['workbenchViewPrefs.update'] = <String, Object?>{
          'revision': 5,
        }
        ..requestGates['workbenchViewPrefs.get'] = (
          started: getStarted,
          release: releaseGet,
        );
      final legacy = _MemoryViewPrefsRepository()
        ..prefs = WorkbenchViewPrefs.defaults.copyWith(searchViewAsTree: false);
      final repository = RuntimeWorkbenchViewPrefsRepository(
        client: client,
        legacyRepository: legacy,
      );

      final echo = repository.load();
      await getStarted.future;
      await repository.save(
        WorkbenchViewPrefs.defaults.copyWith(searchViewAsTree: true),
      );
      expect(legacy.prefs.searchViewAsTree, isTrue);

      releaseGet.complete();
      final echoed = await echo;
      expect(echoed.searchViewAsTree, isTrue);
      expect(legacy.prefs.searchViewAsTree, isTrue);

      await repository.save(
        WorkbenchViewPrefs.defaults.copyWith(searchViewAsTree: false),
      );
      expect(
        client.payloads['workbenchViewPrefs.update']!.last['expectedRevision'],
        5,
      );
    },
  );
}

final class _MemoryViewPrefsRepository implements WorkbenchViewPrefsRepository {
  WorkbenchViewPrefs prefs = .defaults;

  @override
  Stream<WorkbenchViewPrefs> get changes =>
      const Stream<WorkbenchViewPrefs>.empty();

  @override
  Future<WorkbenchViewPrefs> load() async => prefs;

  @override
  Future<void> save(WorkbenchViewPrefs prefs) async {
    this.prefs = prefs;
  }
}

final class _FakeRuntimeHostClient
    implements RuntimeHostClient, RuntimeHostCapabilityClient {
  bool supportsSections = false;
  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      supportsSections && capability == 'workspaceSectionsV1';
  final responses = <String, Object?>{};
  final payloads = <String, List<Map<String, Object?>>>{};
  final requestGates =
      <String, ({Completer<void> started, Completer<void> release})>{};

  @override
  Stream<RuntimeHostEvent> get runtimeEvents =>
      const Stream<RuntimeHostEvent>.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    payloads.putIfAbsent(type, () => <Map<String, Object?>>[]).add(payload);
    final gate = requestGates.remove(type);
    if (gate != null) {
      gate.started.complete();
      await gate.release.future;
    }
    return responses[type];
  }
}
