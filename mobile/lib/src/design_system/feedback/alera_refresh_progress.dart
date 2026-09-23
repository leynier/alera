import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Thin bar for a background refresh over content that stays on screen. It
/// reserves its height while idle, so the content below never shifts.
class const AleraRefreshProgress({super.key, required final bool refreshing})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.progressBarHeight,
      child: refreshing
          ? const LinearProgressIndicator(
              minHeight: AleraTokens.progressBarHeight,
            )
          : null,
    );
  }
}
