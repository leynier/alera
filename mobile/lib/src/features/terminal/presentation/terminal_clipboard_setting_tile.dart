import 'package:alera_mobile/src/features/terminal/application/terminal_clipboard_settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The OSC 52 opt-in as a settings row. Kept as a thin wrapper so the
/// settings screen stays free of provider reads.
class const TerminalClipboardSettingTile({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed =
        ref.watch(terminalClipboardSettingsControllerProvider).value ?? false;
    return Card(
      child: SwitchListTile(
        value: allowed,
        onChanged: (value) => ref
            .read(terminalClipboardSettingsControllerProvider.notifier)
            .setAllowOsc52Clipboard(value),
        title: const Text('Allow OSC 52 Clipboard Writes'),
        subtitle: const Text(
          'Let terminal programs on a paired machine replace this phone\'s clipboard. Off by default.',
        ),
      ),
    );
  }
}
