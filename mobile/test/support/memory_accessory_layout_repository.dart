import 'package:alera_mobile/src/features/terminal/application/accessory_layout_repository.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_layout.dart';

/// In-memory stand-in for the SharedPreferences-backed repository, so widget
/// tests get a resolved layout instead of whatever the platform channel does.
class MemoryAccessoryLayoutRepository implements AccessoryLayoutRepository {
  MemoryAccessoryLayoutRepository([TerminalAccessoryLayout? initial])
    : _layout = initial ?? TerminalAccessoryLayout.defaults();

  TerminalAccessoryLayout _layout;
  int saveCount = 0;

  TerminalAccessoryLayout get saved => _layout;

  @override
  Future<TerminalAccessoryLayout> load() async => _layout;

  @override
  Future<void> save(TerminalAccessoryLayout layout) async {
    _layout = layout;
    saveCount += 1;
  }
}
