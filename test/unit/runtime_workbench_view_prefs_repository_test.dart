import 'package:alera/src/features/workbench/application/workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/infra/runtime_workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seeds an uninitialized runtime from desktop-local preferences', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['workbenchViewPrefs.get'] = <String, Object?>{
        'revision': 0,
        'desktopInitialized': false,
        'prefs': <String, Object?>{'groupBy': 'project'},
      }
      ..responses['workbenchViewPrefs.update'] = <String, Object?>{'revision': 1};
    final local = WorkbenchViewPrefs.defaults.copyWith(groupBy: WorkbenchGroupBy.none, sidebarWidth: 412);
    final legacy = _MemoryViewPrefsRepository()..prefs = local;
    final repository = RuntimeWorkbenchViewPrefsRepository(client: client, legacyRepository: legacy);
    expect(await repository.load(), local);
    expect(client.payloads['workbenchViewPrefs.update']?.single['prefs'], containsPair('groupBy', 'none'));
    expect(legacy.prefs.sidebarWidth, 412);
  });

  test('retains local preferences when the runtime read fails', () async {
    final client = _FakeRuntimeHostClient()
      ..errors['workbenchViewPrefs.get'] = StateError('controlled runtime failure');
    final local = WorkbenchViewPrefs.defaults.copyWith(groupBy: WorkbenchGroupBy.none, sidebarWidth: 412);
    final legacy = _MemoryViewPrefsRepository()..prefs = local;
    final repository = RuntimeWorkbenchViewPrefsRepository(client: client, legacyRepository: legacy);
    expect(await repository.load(), local);
    expect(client.payloads.containsKey('workbenchViewPrefs.update'), isFalse);
  });

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
}

final class _MemoryViewPrefsRepository implements WorkbenchViewPrefsRepository {
  WorkbenchViewPrefs prefs = WorkbenchViewPrefs.defaults;

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

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  final responses = <String, Object?>{};
  final errors = <String, Object>{};
  final payloads = <String, List<Map<String, Object?>>>{};

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
    if (errors[type] case final error?) {
      throw error;
    }
    return responses[type];
  }
}
