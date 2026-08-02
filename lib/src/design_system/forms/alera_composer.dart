import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AleraComposer extends StatefulWidget {
  const AleraComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onClose,
    required this.textActions,
    required this.onTextActionSelected,
    this.enabled = true,
    this.hintText = 'Write a prompt for this terminal',
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onClose;
  final List<AleraTextActionMenuItem> textActions;
  final ValueChanged<String> onTextActionSelected;
  final bool enabled;
  final String hintText;

  @override
  State<AleraComposer> createState() => _AleraComposerState();
}

class _AleraComposerState extends State<AleraComposer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(AleraComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() => setState(() {});

  bool get _canSend =>
      widget.enabled && widget.controller.text.trim().isNotEmpty;

  bool get _hasSelection {
    final value = widget.controller.value;
    final selection = value.selection;
    return selection.isValid &&
        !selection.isCollapsed &&
        selection.start >= 0 &&
        selection.end <= value.text.length;
  }

  void _send() {
    if (_canSend) {
      widget.onSend();
    }
  }

  void _insertLineBreak() {
    if (!widget.enabled) {
      return;
    }
    final value = widget.controller.value;
    final selection = value.selection;
    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;
    widget.controller.value = value.copyWith(
      text: value.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textActionsEnabled = widget.textActions.isNotEmpty && _hasSelection;
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AleraTokens.surfaceVariant,
          borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
          border: Border.all(color: AleraTokens.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.enter): _send,
                const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    _insertLineBreak,
                const SingleActivator(LogicalKeyboardKey.escape):
                    widget.onClose,
              },
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                enabled: widget.enabled,
                minLines: 2,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                style: Theme.of(context).textTheme.bodyMedium,
                contextMenuBuilder: AleraTextActionsScope.buildContextMenu,
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  filled: true,
                  fillColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  contentPadding: const EdgeInsets.fromLTRB(
                    AleraTokens.space12,
                    AleraTokens.space16,
                    AleraTokens.space12,
                    AleraTokens.space8,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.space8,
                0,
                AleraTokens.space8,
                AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _TextActionsMenu(
                        actions: widget.textActions,
                        enabled: textActionsEnabled,
                        onSelected: widget.onTextActionSelected,
                      ),
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  AleraIconButton(
                    key: const ValueKey<String>('composer-send-button'),
                    tooltip: 'Send Prompt',
                    icon: AleraIcons.arrowUp,
                    iconColor: _canSend
                        ? AleraTokens.onAccent
                        : AleraTokens.foregroundFaint,
                    backgroundColor: _canSend
                        ? AleraTokens.accent
                        : AleraTokens.surface,
                    borderRadius: AleraTokens.radiusPill,
                    minSize: AleraTokens.space32,
                    onPressed: _canSend ? _send : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextActionsMenu extends StatelessWidget {
  const _TextActionsMenu({
    required this.actions,
    required this.enabled,
    required this.onSelected,
  });

  final List<AleraTextActionMenuItem> actions;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tooltip = actions.isEmpty
        ? 'No Text Actions Available'
        : enabled
        ? 'Text Actions'
        : 'Select Prompt Text to Use Text Actions';
    return Tooltip(
      message: tooltip,
      child: PopupMenuButton<String>(
        enabled: enabled,
        tooltip: '',
        onSelected: onSelected,
        color: AleraTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          side: const BorderSide(color: AleraTokens.border),
        ),
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          for (final action in actions)
            AleraDropdownEntry<String>(value: action.id, label: action.label),
        ],
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  AleraIcons.ai,
                  size: AleraTokens.space16,
                  color: enabled
                      ? AleraTokens.foregroundMuted
                      : AleraTokens.foregroundFaint,
                ),
                const SizedBox(width: AleraTokens.space6),
                Text(
                  'Text Actions',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: enabled
                        ? AleraTokens.foregroundMuted
                        : AleraTokens.foregroundFaint,
                  ),
                ),
                const SizedBox(width: AleraTokens.space4),
                const Icon(
                  AleraIcons.chevronDown,
                  size: AleraTokens.space16,
                  color: AleraTokens.foregroundFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
