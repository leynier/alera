import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_collapsible_section.dart';
import 'package:alera_automations/alera_automations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The prompt template with its variables highlighted, collapsible, with a
/// copy button.
class const AutomationDetailPrompt({required final String prompt, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5);
    return AleraCollapsibleSection(
      title: 'Prompt',
      initiallyExpanded: true,
      trailing: AleraIconButton(
        tooltip: 'Copy Prompt',
        icon: AleraIcons.copy,
        iconSize: AleraTokens.iconMd,
        onPressed: () => unawaited(() async {
          await Clipboard.setData(ClipboardData(text: prompt));
          AleraToast.publish(
            message: 'Prompt copied.',
            tone: AleraToastTone.success,
          );
        }()),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: AleraTokens.space8),
        child: SelectableText.rich(
          TextSpan(
            style: style,
            children: <InlineSpan>[
              for (final segment in automationTemplateSegments(prompt))
                TextSpan(
                  text: segment.text,
                  style: segment.known == null
                      ? null
                      : AleraTokens.monoCompactStyle.copyWith(
                          color: segment.known!
                              ? AleraTokens.syntaxVariable
                              : AleraTokens.error,
                          backgroundColor: AleraTokens.accentSubtle,
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
