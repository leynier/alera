import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

class MentionFileList extends StatefulWidget {
  const MentionFileList({
    super.key,
    required this.files,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> files;
  final int selectedIndex;
  final ValueChanged<String> onSelect;

  @override
  State<MentionFileList> createState() => _MentionFileListState();
}

class _MentionFileListState extends State<MentionFileList> {
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _itemKeys = [];

  @override
  void initState() {
    super.initState();
    _updateItemKeys();
  }

  @override
  void didUpdateWidget(MentionFileList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.files.length != oldWidget.files.length) {
      _updateItemKeys();
    }
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _scrollToSelected();
    }
  }

  void _updateItemKeys() {
    _itemKeys.clear();
    for (var i = 0; i < widget.files.length; i++) {
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
      constraints: const BoxConstraints(maxHeight: 200),
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
        itemCount: widget.files.length,
        itemBuilder: (context, index) {
          final file = widget.files[index];
          final selected = index == widget.selectedIndex;
          return InkWell(
            key: _itemKeys[index],
            onTap: () => widget.onSelect(file),
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
                  Icon(
                    Icons.insert_drive_file_outlined,
                    size: 14,
                    color: selected
                        ? AleraTokens.accent
                        : AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Text(
                      file,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected
                            ? AleraTokens.accent
                            : AleraTokens.foreground,
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
