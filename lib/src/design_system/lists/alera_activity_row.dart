import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// A keyboard-accessible ledger row that grows with text instead of clipping it.
class AleraActivityRow extends StatelessWidget {
  const AleraActivityRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.metadata,
    this.selected = false,
    this.statusColor = AleraTokens.foregroundMuted,
  });
  final String title;
  final String subtitle;
  final String? metadata;
  final bool selected;
  final Color statusColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: Material(
      color: selected ? AleraTokens.accentSubtle : AleraTokens.surface,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
          ),
          padding: const EdgeInsets.all(AleraTokens.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AleraTokens.space4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: statusColor),
              ),
              if (metadata != null) ...[
                const SizedBox(height: AleraTokens.space4),
                Text(
                  metadata!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AleraTokens.monoCompactStyle,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
