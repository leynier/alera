part of 'agent_quota_settings_group.dart';

class const _QuotaPinButton({
  required final bool pinned,
  required final bool enabled,
  required final ValueChanged<bool> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraIconButton(
      tooltip: pinned
          ? 'Shown in status bar'
          : 'Hidden from status bar - available in the quota panel',
      icon: pinned ? AleraIcons.pin : AleraIcons.pinOff,
      iconSize: 13,
      iconColor: pinned
          ? AleraTokens.foregroundMuted
          : AleraTokens.foregroundFaint,
      onPressed: enabled ? () => onChanged(!pinned) : null,
    );
  }
}

class const _ProviderOrderControl({
  required final List<AgentQuotaProviderId> providers,
  required final ValueChanged<List<AgentQuotaProviderId>> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) {
      return Text(
        'No quota providers enabled',
        textAlign: .right,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: AleraTokens.foregroundFaint),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
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
                    overflow: .ellipsis,
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

class const _ClaudeProfilesControl({
  required final List<ClaudeQuotaProfileSettings> profiles,
  required final bool Function(String profile) isPinned,
  required final void Function(String profile, bool pinned) onPinnedChanged,
  required final ValueChanged<List<ClaudeQuotaProfileSettings>> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        if (profiles.isEmpty)
          Text(
            'No CCS profiles configured',
            textAlign: .right,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundFaint),
          ),
        for (final (index, profile) in profiles.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: AleraTokens.space8),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Text(
                      profile.alias,
                      overflow: .ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      profile.profile,
                      overflow: .ellipsis,
                      style: AleraTokens.monoStyle.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                    Text(
                      profile.showInUsage
                          ? 'Usage: ${profile.usageLabel}'
                          : 'Not shown in Usage',
                      overflow: .ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AleraTokens.foregroundFaint),
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

class const _ClaudeProfileDialog({
  required final ClaudeQuotaProfileSettings? initial,
  required final List<ClaudeQuotaProfileSettings> profiles,
}) extends StatefulWidget {
  @override
  State<_ClaudeProfileDialog> createState() => _ClaudeProfileDialogState();
}

class _ClaudeProfileDialogState extends State<_ClaudeProfileDialog> {
  late final TextEditingController _aliasController;
  late final TextEditingController _profileController;
  late final TextEditingController _usageDisplayNameController;
  late bool _showInUsage;
  String? _error;

  @override
  void initState() {
    super.initState();
    _aliasController = TextEditingController(text: widget.initial?.alias);
    _profileController = TextEditingController(text: widget.initial?.profile);
    _usageDisplayNameController = TextEditingController(
      text: widget.initial?.usageDisplayName ?? widget.initial?.alias,
    );
    _showInUsage = widget.initial?.showInUsage ?? true;
  }

  @override
  void dispose() {
    _aliasController.dispose();
    _profileController.dispose();
    _usageDisplayNameController.dispose();
    super.dispose();
  }

  void _save() {
    final alias = _aliasController.text.trim();
    final profile = _profileController.text.trim();
    final usageDisplayName = _usageDisplayNameController.text.trim();
    final duplicate = widget.profiles.any(
      (candidate) =>
          candidate != widget.initial &&
          (candidate.alias == alias || candidate.profile == profile),
    );
    if (alias.isEmpty || profile.isEmpty) {
      setState(() => _error = 'Alias and profile are required.');
      return;
    }
    if (duplicate) {
      setState(() => _error = 'Alias and profile must be unique.');
      return;
    }
    Navigator.of(context).pop(
      ClaudeQuotaProfileSettings(
        alias: alias,
        profile: profile,
        showInUsage: _showInUsage,
        usageDisplayName: usageDisplayName.isEmpty ? null : usageDisplayName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AleraDialog(
      maxWidth: 480,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space24),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
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
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraCheckbox(
              value: _showInUsage,
              onChanged: (value) => setState(() => _showInUsage = value),
              label: 'Show in Usage',
            ),
            const SizedBox(height: AleraTokens.space8),
            AleraTextField(
              controller: _usageDisplayNameController,
              labelText: 'Usage Name',
              hintText: 'Work',
              enabled: _showInUsage,
              onSubmitted: (_) => _save(),
            ),
            if (_error case final error?) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Text(
                error,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: AleraTokens.error),
              ),
            ],
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisAlignment: .end,
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
