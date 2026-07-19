import 'package:alera_mobile/src/features/terminal/domain/terminal_input_mode.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'terminal_input_mode_controller.g.dart';

/// Per-tab input mode. Compose is the default; switching to direct is a
/// per-terminal opt-in that sticks for the app session but is not persisted
/// across launches (mirrors Orca's scoping with the default inverted).
@Riverpod(keepAlive: true)
class TerminalInputModeController extends _$TerminalInputModeController {
  @override
  TerminalInputMode build(String tabId) {
    return TerminalInputMode.compose;
  }

  void toggle() {
    state = state == TerminalInputMode.compose
        ? TerminalInputMode.direct
        : TerminalInputMode.compose;
  }
}
