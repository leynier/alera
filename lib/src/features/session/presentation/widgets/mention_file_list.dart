import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

class MentionFileList extends StatelessWidget {
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
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          final selected = index == selectedIndex;
          return InkWell(
            onTap: () => onSelect(file),
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
