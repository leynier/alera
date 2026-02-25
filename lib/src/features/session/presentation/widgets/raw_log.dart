import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:flutter/material.dart';

class RawLog extends StatelessWidget {
  const RawLog({super.key, required this.state, required this.expanded});

  final SessionState state;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AleraTokens.durationMid,
      curve: Curves.easeOut,
      height: expanded ? 140 : 0,
      decoration: BoxDecoration(
        border: expanded
            ? Border(top: BorderSide(color: Theme.of(context).dividerColor))
            : null,
      ),
      child: expanded
          ? ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space4,
              ),
              itemCount: state.activityLog.length,
              itemBuilder: (context, index) {
                final logIndex = state.activityLog.length - 1 - index;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AleraTokens.space2,
                  ),
                  child: Text(
                    state.activityLog[logIndex],
                    style: AleraTokens.monoStyle.copyWith(
                      color: AleraTokens.foregroundFaint,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            )
          : null,
    );
  }
}
