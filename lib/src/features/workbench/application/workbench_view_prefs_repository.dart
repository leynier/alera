import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';

abstract interface class WorkbenchViewPrefsRepository {
  Stream<WorkbenchViewPrefs> get changes;

  Future<WorkbenchViewPrefs> load();

  Future<void> save(WorkbenchViewPrefs prefs);
}
