import 'package:alera/src/features/app_window/domain/app_window_state.dart';

abstract interface class AppWindowStateRepository {
  Future<AppWindowState?> load();

  Future<void> save(AppWindowState state);

  Future<void> clear();
}
