import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';

abstract interface class WorkbenchViewPrefsRepository {
  Future<WorkbenchViewPrefs> load();

  Future<void> save(WorkbenchViewPrefs prefs);
}
