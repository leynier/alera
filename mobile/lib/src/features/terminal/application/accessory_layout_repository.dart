import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_layout.dart';

abstract interface class AccessoryLayoutRepository {
  Future<TerminalAccessoryLayout> load();
  Future<void> save(TerminalAccessoryLayout layout);
}
