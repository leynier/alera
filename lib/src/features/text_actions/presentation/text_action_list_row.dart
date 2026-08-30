import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/text_actions/domain/text_actions_settings.dart';
import 'package:flutter/material.dart';

class const TextActionListRow({
  super.key,
  required final TextAction action,
  required final bool selected,
  required final VoidCallback onTap,
  required final VoidCallback onDuplicate,
  required final ValueChanged<bool> onEnabledChanged,
  required final Widget dragHandle,
}) extends StatelessWidget {
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
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Text(
                      action.name,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: .w600,
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
