import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/slash_command.dart';
import 'package:flutter/material.dart';

class SlashCommandList extends StatelessWidget {
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
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
        itemCount: commands.length,
        itemBuilder: (context, index) {
          final cmd = commands[index];
          final selected = index == selectedIndex;
          return InkWell(
            onTap: () => onSelect(cmd),
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
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
