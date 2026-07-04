import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Resource-management scaffold: a fixed-width master column (header with
/// title and optional action, then a scrollable list) beside an expanded
/// detail area with its own scroll context.
///
/// Used by settings resource panes (Projects, Remote Hosts) so entity CRUD
/// screens share one layout.
class AleraMasterDetail extends StatelessWidget {
  const AleraMasterDetail({
    super.key,
    required this.masterTitle,
    this.masterAction,
    required this.master,
    required this.detail,
    this.masterWidth = 240,
  });

  final String masterTitle;
  final Widget? masterAction;
  final Widget master;
  final Widget detail;
  final double masterWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: masterWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(
                  left: AleraTokens.space4,
                  bottom: AleraTokens.space8,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        masterTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AleraTokens.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ?masterAction,
                  ],
                ),
              ),
              Expanded(child: master),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AleraTokens.space16),
          child: VerticalDivider(width: 1, color: AleraTokens.borderSubtle),
        ),
        Expanded(child: detail),
      ],
    );
  }
}
