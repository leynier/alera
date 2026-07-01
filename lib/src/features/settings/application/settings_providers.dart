import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/infra/drift_settings_repository.dart';
import 'package:alera/src/features/settings/infra/github_star_service.dart';
import 'package:alera/src/features/settings/infra/runtime_settings_repository.dart';
import 'package:alera/src/features/settings/infra/system_font_service.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:alera/src/shared/infra/storage/storage_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'settings_providers.g.dart';

@Riverpod(keepAlive: true)
SettingsRepository settingsRepository(Ref ref) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return RuntimeSettingsRepository(
    client: ref.watch(runtimeHostClientProvider),
    legacyRepository: DriftSettingsRepository(db),
    beforeAccess: ref.watch(runtimeStateMigrationProvider).ensureMigrated,
  );
}

@Riverpod(keepAlive: true)
GitHubStarService gitHubStarService(Ref ref) {
  return GitHubStarService(ref.watch(processRunnerProvider));
}

@Riverpod(keepAlive: true)
SystemFontService systemFontService(Ref ref) {
  return IoSystemFontService(ref.watch(processRunnerProvider));
}

@Riverpod(keepAlive: true)
AleraCliSkillService aleraCliSkillService(Ref ref) {
  return AleraCliSkillService(processRunner: ref.watch(processRunnerProvider));
}
