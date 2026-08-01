import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';
import 'package:flutter/material.dart';

class BrowserProfilePickerDialog extends StatelessWidget {
  const BrowserProfilePickerDialog({
    super.key,
    required this.profiles,
    required this.currentProfileId,
    required this.onManageProfiles,
  });

  final List<BrowserProfile> profiles;
  final String currentProfileId;
  final VoidCallback onManageProfiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: AleraTokens.dialogWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.profile,
                  size: AleraTokens.space20,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    'Browser Profile',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                AleraIconButton(
                  tooltip: 'Close',
                  icon: AleraIcons.close,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space8),
            Text(
              'Profiles keep cookies, storage and site permissions separate.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Expanded(
              child: profiles.isEmpty
                  ? const AleraEmptyState(
                      title: 'No browser profiles',
                      message: 'Create a profile to open this page.',
                    )
                  : ListView.builder(
                      itemCount: profiles.length,
                      itemBuilder: (context, index) {
                        final profile = profiles[index];
                        return _BrowserProfileRow(
                          profile: profile,
                          selected: profile.id == currentProfileId,
                          onTap: () => Navigator.of(context).pop(profile.id),
                        );
                      },
                    ),
            ),
            const SizedBox(height: AleraTokens.space12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onManageProfiles();
              },
              icon: const Icon(AleraIcons.settings),
              label: const Text('Manage Profiles'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserProfileRow extends StatelessWidget {
  const _BrowserProfileRow({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final BrowserProfile profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: selected,
      onTap: onTap,
      leading: Icon(
        selected ? AleraIcons.radioOn : AleraIcons.radioOff,
        size: AleraTokens.space16,
        color: selected ? AleraTokens.foreground : AleraTokens.foregroundFaint,
      ),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              profile.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (profile.isDefault) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            const AleraBadge(label: 'Default'),
          ],
        ],
      ),
      subtitle: Text(
        _profileDescription(profile),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foregroundMuted,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      ),
      selectedTileColor: AleraTokens.accentSubtle,
    );
  }
}

String _profileDescription(BrowserProfile profile) {
  final source = profile.source;
  if (source != null) {
    final sourceLabel = switch (source.family) {
      BrowserImportSourceFamily.chrome => 'Chrome',
      BrowserImportSourceFamily.edge => 'Edge',
      BrowserImportSourceFamily.arc => 'Arc',
      BrowserImportSourceFamily.brave => 'Brave',
      BrowserImportSourceFamily.comet => 'Comet',
      BrowserImportSourceFamily.helium => 'Helium',
      BrowserImportSourceFamily.firefox => 'Firefox',
      BrowserImportSourceFamily.safari => 'Safari',
      BrowserImportSourceFamily.manual => 'JSON',
    };
    return source.profileName == null
        ? 'Imported from $sourceLabel'
        : 'Imported from $sourceLabel - ${source.profileName}';
  }
  return profile.isDefault ? 'Shared default profile' : 'Isolated profile';
}
