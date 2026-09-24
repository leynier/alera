import 'package:alera_mobile/src/features/workbench/application/explorer_preferences_repository.dart';
import 'package:alera_mobile/src/features/workbench/domain/explorer_preferences.dart';

/// In-memory stand-in for the SharedPreferences-backed explorer preferences.
class MemoryExplorerPreferencesRepository
    implements ExplorerPreferencesRepository {
  final Map<String, ExplorerPreferences> saved =
      <String, ExplorerPreferences>{};

  @override
  Future<ExplorerPreferences> load(String hostId, String workspaceId) async =>
      saved['$hostId/$workspaceId'] ?? const ExplorerPreferences();

  @override
  Future<void> save(
    String hostId,
    String workspaceId,
    ExplorerPreferences preferences,
  ) async {
    saved['$hostId/$workspaceId'] = preferences;
  }
}
