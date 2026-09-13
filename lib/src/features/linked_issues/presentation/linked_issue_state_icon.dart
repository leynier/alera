import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/linked_issues/domain/issue_state.dart';
import 'package:flutter/material.dart';

/// GitHub-style issue glyph: an open dot, a closed check, or a dashed circle
/// when the state is unknown (URL-only trackers, or not fetched yet).
class const LinkedIssueStateIcon({
  super.key,
  required final IssueState? state,
  final double size = AleraTokens.iconSm,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Icon(
      switch (state) {
        IssueState.open => AleraIcons.issueOpen,
        IssueState.closed => AleraIcons.issueClosed,
        IssueState.unknown || null => AleraIcons.issueUnknown,
      },
      size: size,
      color: switch (state) {
        IssueState.open => AleraTokens.success,
        IssueState.closed => AleraTokens.done,
        IssueState.unknown || null => AleraTokens.foregroundMuted,
      },
    );
  }
}
