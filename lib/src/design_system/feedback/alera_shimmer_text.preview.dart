import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Thinking', group: 'Shimmer Text', size: Size(320, 80))
Widget aleraShimmerTextPreview() =>
    const AleraShimmerScope(child: AleraShimmerText(text: 'Thinking'));

@AleraPreview(name: 'Shared scope', group: 'Shimmer Text', size: Size(320, 160))
Widget aleraShimmerTextSharedScopePreview() => Builder(
  builder: (context) {
    final textTheme = Theme.of(context).textTheme;
    return AleraShimmerScope(
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: <Widget>[
          AleraShimmerText(
            text: 'Working',
            style: textTheme.bodyMedium?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space8),
          AleraShimmerText(text: 'Streaming…', style: textTheme.bodySmall),
          const SizedBox(height: AleraTokens.space8),
          const AleraShimmerText(
            text: 'Sending',
            style: AleraTokens.labelMicroFaintStyle,
          ),
        ],
      ),
    );
  },
);

@AleraPreview(name: 'Without scope', group: 'Shimmer Text', size: Size(320, 80))
Widget aleraShimmerTextStaticPreview() =>
    const AleraShimmerText(text: 'Thinking');
