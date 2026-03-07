import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/slash_command.dart';
import 'package:flutter/material.dart';

class SlashCommandList extends StatefulWidget {
  const SlashCommandList({
    super.key,
    required this.commands,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<SlashCommandDef> commands;
  final int selectedIndex;
  final ValueChanged<SlashCommandDef> onSelect;

  @override
  State<SlashCommandList> createState() => _SlashCommandListState();
}

class _SlashCommandListState extends State<SlashCommandList> {
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _itemKeys = [];

  @override
  void initState() {
    super.initState();
    _updateItemKeys();
  }

  @override
  void didUpdateWidget(SlashCommandList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.commands.length != oldWidget.commands.length) {
      _updateItemKeys();
    }
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _scrollToSelected();
    }
  }

  void _updateItemKeys() {
    _itemKeys.clear();
    for (var i = 0; i < widget.commands.length; i++) {
      _itemKeys.add(GlobalKey());
    }
  }

  void _scrollToSelected() {
    if (widget.selectedIndex < 0 || widget.selectedIndex >= _itemKeys.length) {
      return;
    }

    final key = _itemKeys[widget.selectedIndex];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (key.currentContext != null) {
        Scrollable.ensureVisible(
          key.currentContext!,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.only(bottom: AleraTokens.space4),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
        boxShadow: [
          BoxShadow(
            color: AleraTokens.shadowSoft,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListView.builder(
        controller: _scrollController,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
        itemCount: widget.commands.length,
        itemBuilder: (context, index) {
          final cmd = widget.commands[index];
          final selected = index == widget.selectedIndex;
          return InkWell(
            key: _itemKeys[index],
            onTap: () => widget.onSelect(cmd),
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            child: Container(
              color: selected
                  ? AleraTokens.accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space6,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(
                      '/${cmd.name}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: selected
                            ? AleraTokens.accent
                            : AleraTokens.foreground,
                      ),
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Text(
                      cmd.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AleraTokens.foregroundMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
