import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_preferences.dart';
import 'package:alera_mobile/src/features/codex_chat/infra/local_mobile_codex_preferences_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_codex_preferences_repository.g.dart';

abstract interface class MobileCodexPreferencesRepository {
  Future<MobileCodexPreferences> load(String hostId);
  Future<void> save(String hostId, MobileCodexPreferences preferences);
}

@riverpod
MobileCodexPreferencesRepository mobileCodexPreferencesRepository(Ref ref) =>
    LocalMobileCodexPreferencesRepository();
