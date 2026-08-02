import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_settings.dart';
import 'package:flutter/material.dart';

class TextActionListRow extends StatelessWidget {
  const TextActionListRow({
    super.key,
    required this.action,
    required this.selected,
    required this.onTap,
    required this.onDuplicate,
    required this.onEnabledChanged,
    required this.dragHandle,
  });

  final TextAction action;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final ValueChanged<bool> onEnabledChanged;
  final Widget dragHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: key,
      color: selected ? AleraTokens.accentSubtle : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space6,
          ),
          child: Row(
            children: <Widget>[
              dragHandle,
              const SizedBox(width: AleraTokens.space4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      action.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!action.enabled)
                      Text(
                        'Disabled',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundFaint,
                        ),
                      ),
                  ],
                ),
              ),
              Switch(value: action.enabled, onChanged: onEnabledChanged),
              AleraIconButton(
                tooltip: 'Duplicate',
                icon: AleraIcons.duplicate,
                onPressed: onDuplicate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
