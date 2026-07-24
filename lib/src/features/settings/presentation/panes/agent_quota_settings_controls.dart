part of 'agent_quota_settings_group.dart';

class _QuotaPinButton extends StatelessWidget {
  const _QuotaPinButton({
    required this.pinned,
    required this.enabled,
    required this.onChanged,
  });

  final bool pinned;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AleraIconButton(
      tooltip: pinned
          ? 'Shown In Status Bar'
          : 'Hidden From Status Bar - Available In The Quota Panel',
      icon: pinned ? AleraIcons.pin : AleraIcons.pinOff,
      iconSize: 13,
      iconColor: pinned
          ? AleraTokens.foregroundMuted
          : AleraTokens.foregroundFaint,
      onPressed: enabled ? () => onChanged(!pinned) : null,
    );
  }
}

class _ProviderOrderControl extends StatelessWidget {
  const _ProviderOrderControl({
    required this.providers,
    required this.onChanged,
  });

  final List<AgentQuotaProviderId> providers;
  final ValueChanged<List<AgentQuotaProviderId>> onChanged;

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) {
      return Text(
        'No Quota Providers Enabled',
        textAlign: TextAlign.right,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundFaint),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (index, provider) in providers.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : AleraTokens.space4),
            child: Row(
              children: <Widget>[
                AgentQuotaProviderIcon(
                  provider: provider,
                  size: 16,
                  showTooltip: false,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    provider.label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                AleraIconButton(
                  tooltip: 'Move ${provider.label} Earlier',
                  icon: AleraIcons.chevronUp,
                  onPressed: index == 0
                      ? null
                      : () => onChanged(_moveProvider(providers, index, -1)),
                ),
                const SizedBox(width: AleraTokens.space4),
                AleraIconButton(
                  tooltip: 'Move ${provider.label} Later',
                  icon: AleraIcons.chevronDown,
                  onPressed: index == providers.length - 1
                      ? null
                      : () => onChanged(_moveProvider(providers, index, 1)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

List<AgentQuotaProviderId> _moveProvider(
  List<AgentQuotaProviderId> providers,
  int index,
  int offset,
) {
  final updated = providers.toList();
  final target = index + offset;
  final provider = updated.removeAt(index);
  updated.insert(target, provider);
  return updated;
}

class _ClaudeProfilesControl extends StatelessWidget {
  const _ClaudeProfilesControl({
    required this.profiles,
    required this.isPinned,
    required this.onPinnedChanged,
    required this.onChanged,
  });

  final List<ClaudeQuotaProfileSettings> profiles;
  final bool Function(String profile) isPinned;
  final void Function(String profile, bool pinned) onPinnedChanged;
  final ValueChanged<List<ClaudeQuotaProfileSettings>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (profiles.isEmpty)
          Text(
            'No CCS Profiles Configured',
            textAlign: TextAlign.right,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundFaint),
          ),
        for (final (index, profile) in profiles.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: AleraTokens.space8),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      profile.alias,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      profile.profile,
                      overflow: TextOverflow.ellipsis,
                      style: AleraTokens.monoStyle.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _QuotaPinButton(
                pinned: isPinned(profile.profile),
                enabled: true,
                onChanged: (pinned) => onPinnedChanged(profile.profile, pinned),
              ),
              const SizedBox(width: AleraTokens.space4),
              AleraIconButton(
                tooltip: 'Move ${profile.alias} Earlier',
                icon: AleraIcons.chevronUp,
                onPressed: index == 0
                    ? null
                    : () => onChanged(_moveClaudeProfile(profiles, index, -1)),
              ),
              const SizedBox(width: AleraTokens.space4),
              AleraIconButton(
                tooltip: 'Move ${profile.alias} Later',
                icon: AleraIcons.chevronDown,
                onPressed: index == profiles.length - 1
                    ? null
                    : () => onChanged(_moveClaudeProfile(profiles, index, 1)),
              ),
              const SizedBox(width: AleraTokens.space4),
              AleraIconButton(
                tooltip: 'Edit CCS Profile',
                icon: AleraIcons.edit,
                onPressed: () async {
                  final updated = await _showClaudeProfileDialog(
                    context,
                    initial: profile,
                    profiles: profiles,
                  );
                  if (updated == null) {
                    return;
                  }
                  onChanged(<ClaudeQuotaProfileSettings>[
                    ...profiles.take(index),
                    updated,
                    ...profiles.skip(index + 1),
                  ]);
                },
              ),
              const SizedBox(width: AleraTokens.space4),
              AleraIconButton(
                tooltip: 'Remove CCS Profile',
                icon: AleraIcons.delete,
                onPressed: () => onChanged(<ClaudeQuotaProfileSettings>[
                  ...profiles.take(index),
                  ...profiles.skip(index + 1),
                ]),
              ),
            ],
          ),
        ],
        const SizedBox(height: AleraTokens.space8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              final profile = await _showClaudeProfileDialog(
                context,
                profiles: profiles,
              );
              if (profile != null) {
                onChanged(<ClaudeQuotaProfileSettings>[...profiles, profile]);
              }
            },
            icon: const Icon(AleraIcons.add, size: 14),
            label: const Text('Add CCS Profile'),
          ),
        ),
      ],
    );
  }
}

List<ClaudeQuotaProfileSettings> _moveClaudeProfile(
  List<ClaudeQuotaProfileSettings> profiles,
  int index,
  int offset,
) {
  final updated = profiles.toList();
  final target = index + offset;
  final profile = updated.removeAt(index);
  updated.insert(target, profile);
  return updated;
}

Future<ClaudeQuotaProfileSettings?> _showClaudeProfileDialog(
  BuildContext context, {
  ClaudeQuotaProfileSettings? initial,
  required List<ClaudeQuotaProfileSettings> profiles,
}) {
  return showDialog<ClaudeQuotaProfileSettings>(
    context: context,
    builder: (context) =>
        _ClaudeProfileDialog(initial: initial, profiles: profiles),
  );
}

class _ClaudeProfileDialog extends StatefulWidget {
  const _ClaudeProfileDialog({required this.initial, required this.profiles});

  final ClaudeQuotaProfileSettings? initial;
  final List<ClaudeQuotaProfileSettings> profiles;

  @override
  State<_ClaudeProfileDialog> createState() => _ClaudeProfileDialogState();
}

class _ClaudeProfileDialogState extends State<_ClaudeProfileDialog> {
  late final TextEditingController _aliasController;
  late final TextEditingController _profileController;
  String? _error;

  @override
  void initState() {
    super.initState();
    _aliasController = TextEditingController(text: widget.initial?.alias);
    _profileController = TextEditingController(text: widget.initial?.profile);
  }

  @override
  void dispose() {
    _aliasController.dispose();
    _profileController.dispose();
    super.dispose();
  }

  void _save() {
    final alias = _aliasController.text.trim();
    final profile = _profileController.text.trim();
    final duplicate = widget.profiles.any(
      (candidate) =>
          candidate != widget.initial &&
          (candidate.alias == alias || candidate.profile == profile),
    );
    if (alias.isEmpty || profile.isEmpty) {
      setState(() => _error = 'Alias And Profile Are Required.');
      return;
    }
    if (duplicate) {
      setState(() => _error = 'Alias And Profile Must Be Unique.');
      return;
    }
    Navigator.of(
      context,
    ).pop(ClaudeQuotaProfileSettings(alias: alias, profile: profile));
  }

  @override
  Widget build(BuildContext context) {
    return AleraDialog(
      maxWidth: 480,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.initial == null ? 'Add CCS Profile' : 'Edit CCS Profile',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.space16),
            AleraTextField(
              controller: _aliasController,
              labelText: 'Alias',
              hintText: 'ccwork',
              autofocus: true,
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _profileController,
              labelText: 'CCS Profile',
              hintText: 'work',
              onSubmitted: (_) => _save(),
            ),
            if (_error case final error?) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Text(
                error,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AleraTokens.error),
              ),
            ],
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: _save,
                  child: const Text('Save Profile'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
