import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/composer_draft_item.dart';
import 'package:flutter/material.dart';

class ComposerDraftItemBar extends StatelessWidget {
  const ComposerDraftItemBar({
    super.key,
    required this.items,
    required this.onRemove,
  });

  final List<ComposerDraftItem> items;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space8,
        AleraTokens.space8,
        AleraTokens.space8,
        0,
      ),
      child: SizedBox(
        height: 28,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: AleraTokens.space4),
          itemBuilder: (context, index) {
            final item = items[index];
            return _DraftItemChip(
              item: item,
              onRemove: () => onRemove(item.id),
            );
          },
        ),
      ),
    );
  }
}

class _DraftItemChip extends StatelessWidget {
  const _DraftItemChip({required this.item, required this.onRemove});

  final ComposerDraftItem item;
  final VoidCallback onRemove;

  IconData get _icon {
    switch (item.kind) {
      case ComposerDraftItemKind.skill:
        return Icons.bolt_outlined;
      case ComposerDraftItemKind.mention:
        return Icons.alternate_email;
    }
  }

  String get _label {
    final tokenText = item.tokenText;
    if (tokenText != null && tokenText.isNotEmpty) {
      return tokenText;
    }
    return item.name;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: AleraTokens.space8),
            child: Icon(
              _icon,
              size: 14,
              color: AleraTokens.foregroundMuted,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space6),
            child: Text(
              _label,
              style: const TextStyle(
                fontSize: 11,
                color: AleraTokens.foregroundMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: onRemove,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
            child: const Padding(
              padding: EdgeInsets.all(AleraTokens.space4),
              child: Icon(
                Icons.close,
                size: 12,
                color: AleraTokens.foregroundFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
