import 'package:alera/src/features/settings/domain/alera_settings.dart';

abstract interface class SettingsRepository {
  Future<AleraSettings> load();

  Future<void> save(AleraSettings settings);
}
