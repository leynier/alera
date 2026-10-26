import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_composer_menu.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

const List<AleraComposerMenuItem> _files = <AleraComposerMenuItem>[
  AleraComposerMenuItem(
    id: 'main',
    label: 'main.dart',
    detail: 'lib',
    leading: AleraFileIcon(
      pathOrName: 'main.dart',
      kind: .file,
      size: AleraTokens.iconMd,
    ),
  ),
  AleraComposerMenuItem(
    id: 'composer',
    label: 'alera_composer.dart',
    detail: 'lib/src/design_system/forms',
    leading: AleraFileIcon(
      pathOrName: 'alera_composer.dart',
      kind: .file,
      size: AleraTokens.iconMd,
    ),
  ),
  AleraComposerMenuItem(
    id: 'readme',
    label: 'README.md',
    leading: AleraFileIcon(
      pathOrName: 'README.md',
      kind: .file,
      size: AleraTokens.iconMd,
    ),
  ),
];

const List<AleraComposerMenuItem> _commands = <AleraComposerMenuItem>[
  AleraComposerMenuItem(
    id: 'model',
    label: '/model',
    detail: 'Open the agent and model picker.',
    leading: Icon(AleraIcons.agent, size: AleraTokens.iconMd),
  ),
  AleraComposerMenuItem(
    id: 'plan',
    label: '/plan',
    detail: 'Plan before acting, from the next message.',
    leading: Icon(AleraIcons.plan, size: AleraTokens.iconMd),
  ),
  AleraComposerMenuItem(
    id: 'default',
    label: '/default',
    disabledReason: 'Default mode is already on.',
    leading: Icon(AleraIcons.code, size: AleraTokens.iconMd),
  ),
];

@AleraPreview(
  name: 'File mentions',
  group: 'Composer menu',
  size: Size(420, 200),
)
Widget aleraComposerMenuFilesPreview() => const Padding(
  padding: EdgeInsets.all(AleraTokens.space16),
  child: AleraComposerMenu(
    items: _files,
    activeIndex: 1,
    semanticsLabel: 'File Mentions',
    title: 'Files',
    onPick: _ignore,
  ),
);

@AleraPreview(name: 'Empty', group: 'Composer menu', size: Size(420, 120))
Widget aleraComposerMenuEmptyPreview() => const Padding(
  padding: EdgeInsets.all(AleraTokens.space16),
  child: AleraComposerMenu(
    items: <AleraComposerMenuItem>[],
    activeIndex: 0,
    semanticsLabel: 'File Mentions',
    title: 'Files',
    emptyMessage: 'No matching files.',
    onPick: _ignore,
  ),
);

/// Type `/` in the field; Up, Down, Enter, Tab and Escape drive the menu
/// while the field keeps focus.
@AleraPreview(
  name: 'Anchored to a field',
  group: 'Composer menu',
  size: Size(480, 320),
)
Widget aleraComposerMenuAnchorPreview() => const _AnchorDemo();

void _ignore(int _) {}

class const _AnchorDemo() extends StatefulWidget {
  @override
  State<_AnchorDemo> createState() => _AnchorDemoState();
}

class _AnchorDemoState extends State<_AnchorDemo> {
  final TextEditingController _text = TextEditingController(text: '/');
  late final FocusNode _focus = FocusNode(onKeyEvent: _handleKey);
  int _active = 0;
  bool _dismissed = false;

  bool get _open => !_dismissed && _text.text.startsWith('/');

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() => _dismissed = false));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!_open) return KeyEventResult.ignored;
    switch (AleraComposerMenu.keyFor(event)) {
      case null:
        return KeyEventResult.ignored;
      case AleraComposerMenuKey.previous:
        setState(() => _active = AleraComposerMenu.step(_active, 3, -1));
      case AleraComposerMenuKey.next:
        setState(() => _active = AleraComposerMenu.step(_active, 3, 1));
      case AleraComposerMenuKey.pick:
        _pick(_active);
      case AleraComposerMenuKey.dismiss:
        setState(() => _dismissed = true);
    }
    return KeyEventResult.handled;
  }

  void _pick(int index) {
    if (!_commands[index].enabled) return;
    _text.clear();
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: .bottomCenter,
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: AleraComposerMenuAnchor(
        open: _open,
        menu: AleraComposerMenu(
          items: _commands,
          activeIndex: _active,
          semanticsLabel: 'Commands',
          title: 'Commands',
          onActiveChanged: (index) => setState(() => _active = index),
          onPick: _pick,
        ),
        child: TextField(
          controller: _text,
          focusNode: _focus,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Type / for commands'),
        ),
      ),
    ),
  );
}
