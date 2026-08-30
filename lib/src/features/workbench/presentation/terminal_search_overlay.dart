import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/workbench/presentation/terminal_search_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class const TerminalSearchOverlay({
  super.key,
  required final TerminalSearchController controller,
  required final VoidCallback onClose,
}) extends StatefulWidget {
  @override
  State<TerminalSearchOverlay> createState() => _TerminalSearchOverlayState();
}

class _TerminalSearchOverlayState extends State<TerminalSearchOverlay> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.controller.query);
    _focusNode = FocusNode(debugLabel: 'TerminalSearch');
    widget.controller.addListener(_handleControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _textController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _textController.text.length,
        );
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }
    if (_textController.text != widget.controller.query) {
      _textController.value = TextEditingValue(
        text: widget.controller.query,
        selection: .collapsed(offset: widget.controller.query.length),
      );
    }
    setState(() {});
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      widget.controller.next();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final matchNumber = widget.controller.selectedMatchNumber;
    final countLabel = widget.controller.query.isEmpty
        ? null
        : widget.controller.matchCount == 0
        ? 'No results'
        : '$matchNumber/${widget.controller.matchCount}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        border: Border.all(color: AleraTokens.borderSubtle),
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: AleraTokens.shadowSoft,
            blurRadius: AleraTokens.space8,
            offset: Offset(0, AleraTokens.space4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space4),
        child: Focus(
          onKeyEvent: _handleKey,
          child: Row(
            children: <Widget>[
              Expanded(
                child: AleraTextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  hintText: 'Search Terminal',
                  dense: true,
                  fillColor: AleraTokens.surfaceVariant,
                  onChanged: widget.controller.setQuery,
                ),
              ),
              if (countLabel != null) ...<Widget>[
                const SizedBox(width: AleraTokens.space8),
                Text(countLabel, style: AleraTokens.monoStyle),
              ],
              const SizedBox(width: AleraTokens.space4),
              AleraIconButton(
                tooltip: 'Previous Match',
                icon: AleraIcons.chevronUp,
                onPressed: widget.controller.matchCount == 0
                    ? null
                    : widget.controller.previous,
                minSize: AleraTokens.space32,
              ),
              AleraIconButton(
                tooltip: 'Next Match',
                icon: AleraIcons.chevronDown,
                onPressed: widget.controller.matchCount == 0
                    ? null
                    : widget.controller.next,
                minSize: AleraTokens.space32,
              ),
              AleraIconButton(
                tooltip: 'Close Search',
                icon: AleraIcons.close,
                onPressed: widget.onClose,
                minSize: AleraTokens.space32,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
