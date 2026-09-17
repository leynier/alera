import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/icons/alera_linked_worktree_icon.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Next to branch', group: 'Linked Worktree Icon')
Widget aleraLinkedWorktreeIconPreview() => const Row(
  mainAxisSize: .min,
  children: <Widget>[
    AleraLinkedWorktreeIcon(size: AleraTokens.iconMd),
    SizedBox(width: AleraTokens.space12),
    Icon(
      AleraIcons.gitBranch,
      size: AleraTokens.iconMd,
      color: AleraTokens.foregroundMuted,
    ),
  ],
);
