import 'package:alera_mobile/src/features/workbench/domain/explorer_preferences.dart';
import 'package:alera_mobile/src/features/workbench/infra/local_explorer_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);

  test('round-trips preferences per host and workspace', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final repository = LocalExplorerPreferencesRepository();

    expect(
      await repository.load('host-1', 'workspace-1'),
      const ExplorerPreferences(),
    );
    await repository.save(
      'host-1',
      'workspace-1',
      const ExplorerPreferences(hideIgnored: false, sourceControlRoot: 'api'),
    );

    expect(
      await repository.load('host-1', 'workspace-1'),
      const ExplorerPreferences(hideIgnored: false, sourceControlRoot: 'api'),
    );
    expect(
      await repository.load('host-1', 'workspace-2'),
      const ExplorerPreferences(),
    );
  });

  test('falls back to defaults when storage is unavailable', () async {
    SharedPreferencesAsyncPlatform.instance = null;
    final repository = LocalExplorerPreferencesRepository();

    expect(
      await repository.load('host-1', 'workspace-1'),
      const ExplorerPreferences(),
    );
    await repository.save(
      'host-1',
      'workspace-1',
      const ExplorerPreferences(hideIgnored: false),
    );
  });

  test('ignores a blank stored root', () {
    expect(
      ExplorerPreferences.fromJson(const <String, Object?>{
        'hideIgnored': true,
        'sourceControlRoot': '  ',
      }).sourceControlRoot,
      isNull,
    );
  });
}
