import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

class const BrowserTabDragPlaceholder({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: ValueKey<String>('browser-tab-drag-placeholder'),
      color: AleraTokens.bg,
      child: AleraEmptyState(
        icon: AleraIcons.public,
        title: 'Browser temporarily hidden',
        message: 'Release the tab to restore this page.',
      ),
    );
  }
}
