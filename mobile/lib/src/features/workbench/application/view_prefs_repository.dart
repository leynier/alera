import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';

abstract interface class ViewPrefsRepository {
  Future<MobileViewPrefs> load(String hostId);
  Future<void> save(String hostId, MobileViewPrefs prefs);
}
