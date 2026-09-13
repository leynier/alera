import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/linked_issues/domain/mobile_linked_issue.dart';
import 'package:flutter/material.dart';

/// Issue glyph for a workspace row, with the issue as its tooltip and
/// semantics label. Opening the issue lives in the row's actions sheet.
class const MobileLinkedIssueIcon({
  super.key,
  required final MobileLinkedIssue issue,
  final double size = 12,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: mobileLinkedIssueTooltip(issue),
      child: Icon(
        issue.isOpen
            ? AleraIcons.issueOpen
            : issue.isClosed
            ? AleraIcons.issueClosed
            : AleraIcons.issueUnknown,
        size: size,
        color: issue.isOpen ? AleraTokens.success : AleraTokens.foregroundMuted,
        semanticLabel: 'Linked issue ${issue.reference}',
      ),
    );
  }
}

String mobileLinkedIssueTooltip(MobileLinkedIssue issue) {
  final title = issue.title;
  return <String>[
    title == null
        ? 'Issue ${issue.reference}'
        : 'Issue ${issue.reference}: $title',
    ?issue.displayState,
    if (issue.fetchError case final error?) 'Details unavailable: $error',
  ].join('\n');
}
