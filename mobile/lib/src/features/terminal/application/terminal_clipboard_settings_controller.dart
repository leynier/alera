import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'terminal_clipboard_settings_controller.g.dart';

/// Device-local key for the OSC 52 clipboard-write opt-in.
///
/// Stored on the phone rather than with the host's portable settings because
/// it governs what programs on any paired machine may do to this device's
/// clipboard, the same way the desktop setting governs its own.
const String kTerminalOsc52ClipboardPreferenceKey =
    'alera.mobile.terminal.allowOsc52Clipboard';

/// Whether terminal programs may replace the phone's clipboard through OSC 52.
///
/// Off by default, mirroring the desktop's `allowOsc52Clipboard`: any byte
/// stream the terminal renders could otherwise swap the clipboard under the
/// user, and a SnackBar is easy to miss.
@Riverpod(keepAlive: true)
class TerminalClipboardSettingsController
    extends _$TerminalClipboardSettingsController {
  static final Logger _log = Logger('TerminalClipboardSettings');

  @override
  Future<bool> build() async {
    try {
      return await SharedPreferencesAsync().getBool(
            kTerminalOsc52ClipboardPreferenceKey,
          ) ??
          false;
    } on Object catch (error, stackTrace) {
      // Staying off is the safe answer when the stored choice cannot be read.
      _log.warning(
        'failed to read the OSC 52 clipboard preference',
        error,
        stackTrace,
      );
      return false;
    }
  }

  Future<void> setAllowOsc52Clipboard(bool enabled) async {
    state = AsyncData(enabled);
    try {
      await SharedPreferencesAsync().setBool(
        kTerminalOsc52ClipboardPreferenceKey,
        enabled,
      );
    } on Object catch (error, stackTrace) {
      _log.warning(
        'failed to persist the OSC 52 clipboard preference',
        error,
        stackTrace,
      );
    }
  }
}
