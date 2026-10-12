import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/chips/alera_property_chip.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Chip anchor', group: 'Popover', size: Size(360, 260))
Widget aleraPopoverPreview() => const _PopoverDemo();

class const _PopoverDemo() extends StatefulWidget {
  @override
  State<_PopoverDemo> createState() => _PopoverDemoState();
}

class _PopoverDemoState extends State<_PopoverDemo> {
  static const List<String> _agents = <String>['Opus', 'Codex', 'Cursor'];

  final AleraPopoverController _controller = AleraPopoverController()..open();
  String _agent = _agents.first;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: .topCenter,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => AleraPopover(
          controller: _controller,
          toggleOnAnchorTap: false,
          width: AleraTokens.contextMenuWidth,
          builder: (context, close) => Padding(
            padding: const EdgeInsets.all(AleraTokens.space4),
            child: Column(
              mainAxisSize: .min,
              children: <Widget>[
                for (final agent in _agents)
                  AleraMenuItem(
                    label: agent,
                    selected: agent == _agent,
                    onTap: () {
                      setState(() => _agent = agent);
                      close();
                    },
                  ),
              ],
            ),
          ),
          child: AleraPropertyChip(
            icon: AleraIcons.agent,
            value: _agent,
            active: _controller.isOpen,
            onTap: _controller.toggle,
          ),
        ),
      ),
    );
  }
}
