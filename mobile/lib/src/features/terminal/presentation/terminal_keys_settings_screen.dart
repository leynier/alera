import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_accessory_layout_controller.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_key.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_layout.dart';
import 'package:alera_mobile/src/features/terminal/presentation/custom_key_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configuration for the terminal quick-key bar: drag to reorder, toggle
/// visibility, add or delete custom key combos, reset to defaults. Changes
/// apply live to every open terminal.
class const TerminalKeysSettingsScreen({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(terminalAccessoryLayoutControllerProvider);
    final controller = ref.read(
      terminalAccessoryLayoutControllerProvider.notifier,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal Quick Keys'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Add Custom Key',
            onPressed: () async {
              final result = await showCustomKeyDialog(context);
              if (result != null) {
                await controller.addCustomKey(
                  key: result.key,
                  modifiers: result.modifiers,
                );
              }
            },
            icon: const Icon(Icons.add),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'reset') {
                controller.resetToDefaults();
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'reset',
                child: Text('Reset To Defaults'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: switch (layout) {
          AsyncData(value: final current) => _KeyList(
            layout: current,
            controller: controller,
          ),
          AsyncError(:final error) => Center(child: Text(error.toString())),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class const _KeyList({
  required final TerminalAccessoryLayout layout,
  required final TerminalAccessoryLayoutController controller,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final keys = layout.orderedKeys();
    final customIds = <String>{
      for (final custom in layout.customKeys) custom.id,
    };
    return ReorderableListView.builder(
      padding: const .only(bottom: AleraTokens.spaceXxl),
      itemCount: keys.length,
      onReorderItem: controller.moveKey,
      itemBuilder: (context, index) {
        final key = keys[index];
        final isCustom = customIds.contains(key.id);
        return SwitchListTile(
          key: ValueKey<String>(key.id),
          value: !layout.hiddenIds.contains(key.id),
          onChanged: (visible) => controller.setKeyVisible(key.id, visible),
          title: Text(
            key.label,
            style: switch (key) {
              // An action key spells a word, not a key cap, so the mono face
              // that makes Ctrl+C read as a key would only look broken here.
              TerminalAccessoryActionKey() => null,
              TerminalAccessoryBytesKey() => const TextStyle(
                fontFamily: AleraTokens.monoFontFamily,
              ),
            },
          ),
          subtitle: Text(isCustom ? 'Custom Key' : key.accessibilityLabel),
          secondary: isCustom
              ? IconButton(
                  tooltip: 'Delete Custom Key',
                  onPressed: () => controller.removeCustomKey(key.id),
                  icon: const Icon(Icons.delete_outline),
                )
              : ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_handle),
                ),
        );
      },
    );
  }
}
