import 'package:alera_mobile/src/features/workbench/domain/explorer_preferences.dart';

abstract interface class ExplorerPreferencesRepository {
  Future<ExplorerPreferences> load(String hostId, String workspaceId);

  Future<void> save(
    String hostId,
    String workspaceId,
    ExplorerPreferences preferences,
  );
}
