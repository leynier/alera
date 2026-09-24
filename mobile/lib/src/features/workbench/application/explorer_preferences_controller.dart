import 'package:alera_mobile/src/features/workbench/application/explorer_preferences_repository.dart';
import 'package:alera_mobile/src/features/workbench/domain/explorer_preferences.dart';
import 'package:alera_mobile/src/features/workbench/infra/local_explorer_preferences_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'explorer_preferences_controller.g.dart';

@Riverpod(keepAlive: true)
ExplorerPreferencesRepository explorerPreferencesRepository(Ref ref) {
  return LocalExplorerPreferencesRepository();
}

/// Shared by the Explorer and Source Control panels so a root chosen in one is
/// what the other reads.
@Riverpod(keepAlive: true)
class ExplorerPreferencesController extends _$ExplorerPreferencesController {
  @override
  Future<ExplorerPreferences> build(String hostId, String workspaceId) {
    return ref
        .watch(explorerPreferencesRepositoryProvider)
        .load(hostId, workspaceId);
  }

  Future<void> setHideIgnored(bool value) =>
      _update((current) => current.withHideIgnored(value));

  Future<void> setSourceControlRoot(String? relativeRoot) =>
      _update((current) => current.withSourceControlRoot(relativeRoot));

  Future<void> _update(
    ExplorerPreferences Function(ExplorerPreferences) transform,
  ) async {
    final next = transform(await future);
    state = AsyncData(next);
    await ref
        .read(explorerPreferencesRepositoryProvider)
        .save(hostId, workspaceId, next);
  }
}
