import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/chips/alera_inline_chip.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Skill In Text', group: 'Inline Chip')
Widget aleraInlineChipTextPreview() => Container(
  padding: const EdgeInsets.all(AleraTokens.space12),
  color: AleraTokens.accentSubtle,
  child: Text.rich(
    TextSpan(
      children: <InlineSpan>[
        const TextSpan(text: 'Please '),
        AleraInlineChip.span(
          label: 'Code Review',
          icon: AleraIcons.skill,
          tooltip: r'$code-review',
        ),
        const TextSpan(text: ' the last commit.'),
      ],
    ),
  ),
);

@AleraPreview(name: 'Without Icon', group: 'Inline Chip')
Widget aleraInlineChipPlainPreview() =>
    const AleraInlineChip(label: 'Deploy App');
