import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';
import 'package:flutter/material.dart';

const double _kSectionIconSize = 18;

class SettingsContent extends StatelessWidget {
  const SettingsContent({
    super.key,
    required this.section,
    required this.onClose,
  });

  final SettingsSectionData section;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(AleraTokens.space24),
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Icon(
                  section.icon,
                  size: _kSectionIconSize,
                  color: AleraTokens.accent,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(section.title, style: theme.textTheme.titleLarge),
                ),
                if (section.onReset != null) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  TextButton(
                    onPressed: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      await Future<void>.delayed(Duration.zero);
                      await section.onReset!();
                    },
                    child: Text('Reset ${section.title}'),
                  ),
                ],
                const SizedBox(width: AleraTokens.space4),
                AleraIconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: AleraIcons.close,
                  minSize: 34,
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space4),
            Text(
              section.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: AleraTokens.space20),
        section.builder(context),
      ],
    );
  }
}

class NoSettingsResults extends StatelessWidget {
  const NoSettingsResults({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        const Positioned.fill(
          child: AleraEmptyState(message: 'No settings found.'),
        ),
        Positioned(
          top: AleraTokens.space16,
          right: AleraTokens.space16,
          child: AleraIconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: AleraIcons.close,
            minSize: 28,
          ),
        ),
      ],
    );
  }
}
