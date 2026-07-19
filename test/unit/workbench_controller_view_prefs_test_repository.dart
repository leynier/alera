part of 'workbench_controller_test.dart';

class _FakeWorkbenchViewPrefsRepository
    implements WorkbenchViewPrefsRepository {
  WorkbenchViewPrefs prefs = WorkbenchViewPrefs.defaults;
  Object? loadError;
  Object? saveError;
  int saveCount = 0;

  @override
  Stream<WorkbenchViewPrefs> get changes => const Stream.empty();

  @override
  Future<WorkbenchViewPrefs> load() async {
    if (loadError case final Object error) {
      throw error;
    }
    return prefs;
  }

  @override
  Future<void> save(WorkbenchViewPrefs prefs) async {
    saveCount += 1;
    if (saveError case final Object error) {
      throw error;
    }
    this.prefs = prefs;
  }
}
