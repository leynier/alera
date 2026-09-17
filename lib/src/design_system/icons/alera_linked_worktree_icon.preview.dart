import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/icons/alera_linked_worktree_icon.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Next to branch', group: 'Linked worktree icon')
Widget aleraLinkedWorktreeIconPreview() => const Row(
  mainAxisSize: .min,
  children: <Widget>[
    AleraLinkedWorktreeIcon(size: AleraTokens.iconLg),
    SizedBox(width: AleraTokens.space12),
    Icon(
      AleraIcons.gitBranch,
      size: AleraTokens.iconLg,
      color: AleraTokens.foregroundMuted,
    ),
  ],
);
